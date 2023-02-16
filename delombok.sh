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
set -eu


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
java -jar "$lombokjar" delombok \
  --verbose \
  --onlyChanged --nocopy \
  "${classpath_arg}" \
  -f suppressWarnings:skip \
  -f generated:skip \
  -f generateDelombokComment:skip \
  -f javaLangAsFQN:skip \
  "$src_dir" \
  --target="$delombok_src_dir"


echo "Overwrite delomboked java files"
cp -r ${delombok_src_dir}/* "${src_dir}"/


# Process all the (delomboked) java files
echo "Post-process (delomboked) java files"

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
  find "${delombok_src_dir}" -type f -exec cat {} \;
fi

echo "All done"
