#!/usr/bin/env bash

# Get input
if [ -z "$1" ]; then
  base_dir='.'
else
  base_dir="$1"
fi

if [ -z "$2" ]; then
  src_dir="${base_dir}/src"
else
  src_dir="${base_dir}/${2}"
fi

if [ "$3" == "true" ] || [ "$3" == "t" ]; then
  print_delombok=1
else
  print_delombok=0
fi

echo "Using base directory: ${base_dir}"
echo "Using source directory: ${src_dir}"


# Trap all the errors and exit on undefined variable references
set -euo pipefail


# Do we need to delombok anything?
if ! git grep -q "^import lombok" '*.java'; then
  echo "No files contain Lombok, so nothing to do. Exit with success."
  exit 0
fi


# Download Lombok Jar
lombokjar=$(mktemp --suffix=.jar --tmpdir lombok-XXXXXXXXXX)
curl --silent "https://projectlombok.org/downloads/lombok.jar" -o "$lombokjar"
echo "Downloaded Lombok Jar to ${lombokjar}"


# Get the classpath (needed for @Delegate to delombok properly)
if [ -f "pom.xml" ]; then
  echo "Getting classpath for Maven project"
  mvn --quiet dependency:build-classpath -Dmdep.outputFile=classpath.txt
  classpath=$(cat classpath.txt)
else
  echo "Unsupported build system. Cannot get classpath! Files containing @Delegate will have errors!"
  classpath=''
fi


# Run delombok
delombok_src_dir=src-delombok
echo "Delomboking ${src_dir} into ${delombok_src_dir}"
mkdir $delombok_src_dir
if [ -z "$classpath" ]; then
  classpath_arg='--classpath=.'
else
  classpath_arg="--classpath=${classpath}"
fi

delombok_log='delombok.log'
echo "Delombok errors will be written to $delombok_log"

java -jar "$lombokjar" delombok \
  --verbose \
  --onlyChanged --nocopy \
  "${classpath_arg}" \
  -f suppressWarnings:skip \
  -f generated:skip \
  -f generateDelombokComment:skip \
  -f javaLangAsFQN:skip \
  "$src_dir" \
  --target="$delombok_src_dir" 2>&1 | tee $delombok_log

# Check log file for errors that indicate a problem

# Check for 'error: cannot find symbol' and stop if found
if grep -Eiq 'error: cannot find symbol' "$delombok_log"; then
    echo "ERROR: There were 'cannot find symbol' errors during delombok."
    echo 'Make sure all utility methods in classes annotated with @UtilityClass have the static modifier.'
    echo 'Any @UtilityClass with methods that do not have static will cause problems when running delombok.'
    echo 'If all utility methods in classes with @UtilityClass have static, there is some other problem.'
    exit 1
fi


# Check delombok_src_dir and stop if empty
if ! find src-delombok -type f -name '*.java' -print -quit | grep -q .; then
  echo "No files were delomboked, so there's nothing more to do..."
  exit 0
fi


echo "Overwrite delomboked java files into $src_dir"
cp -r ${delombok_src_dir}/* "${src_dir}"/


# Process all the (delomboked) java files
echo "Post-process (delomboked) java files"
echo "  1. Replace imports of lombok.* with lombok.NonNull"
echo "  2. Remove any remaining lombok imports (except NonNull)"
echo "  3. Remove any @Generated annotations"

find "$src_dir" -name "*.java" -type f | while read -r java_file; do
  echo "Processing: ${java_file}"

  # Replace imports of lombok.* with lombok.NonNull, otherwise the delomboked
  # file will still be ignored by CodeQL
  sed -r -i 's/^import[[:space:]]+lombok\.\*;$/import lombok.NonNull;/g' "$java_file"

  # Remove any remaining lombok imports (except NonNull)
  sed -r -i '/^.*NonNull;/! s/import[[:space:]]+lombok\..*;//g' "$java_file"

  # Remove any @Generated annotations, as they would prevent CodeQL from analyzing
  # the file. This can happen if, for example, already delomboked code is stored
  # in the repository.
  sed -r -i 's/@Generated( |$)//g' "$java_file"
done

if [ "$print_delombok" -eq 1 ]; then
  echo "Delomboked source files:"
  find "${delombok_src_dir}" -type f -print -exec cat -n {} \;
fi

echo "All done"
