# delombok-action
This is a custom delombok action for use with CodeQL workflows.

## Example Usage

In a CodeQL workflow where the project being analyzed uses Lombok, you can add the following after initializing CodeQL and _before_ building the code. For example:

```yaml
    steps:
    - name: Checkout repository
      uses: actions/checkout@v3

    - name: Initialize CodeQL
      uses: github/codeql-action/init@v2
      with:
        languages: ${{ matrix.language }}
        queries: security-extended,security-and-quality
    
    # other steps, e.g. use cache action for Maven repository   

    # Delombok before building code
    - name: Delombok
      uses: sleberknight/delombok-action@v0.7.0
      
    # Now build the code
    - name: Autobuild
      uses: github/codeql-action/autobuild@v2

    - name: Perform CodeQL Analysis
      uses: github/codeql-action/analyze@v2
      with:
        category: "/language:${{matrix.language}}"
```

## Background

This action was inspired by the following:

* https://github.com/advanced-security/delombok
* https://github.com/advanced-security/delombok-action

In contrast to those delombok actions, this one does _not_ attempt to reformat or change the delomboked source files _in any way_. It just runs delombok. Since delomboked code tends to be significantly different than the original source code with Lombok annotations anyway, trying to make them look anything like the original doesn't seem to be worth it.

When CodeQL flags an issue in a delomboked source file, the line numbers never match up anyway, and you have to determine whether the issue is in the code generated by Lombok or in your own code. One example is that CodeQL flags source code that uses Lombok's `@With` annotation with a [_Reference equality test on strings_](https://codeql.github.com/codeql-query-help/java/java-reference-equality-on-strings/)  violation. To figure this out, you need to look at the delomboked code to see that it isn't an issue, but rather a slight optimization that Lombok is using. For example, say you have the following simple class:

```java
@Value
public class User {
    String username;
    @With String password;
}
```

The delomboked code for `@With` is:

```java
    /**
     * @return a clone of this object, except with this updated property (returns {@code this} if an identical value is passed).
     */
    public User withPassword(final String password) {
        return this.password == password ? this : new User(this.username, password);
    }
 ```
 
 CodeQL flags `this.password == password` as an error violating the `java/reference-equality-on-strings` rule (_Reference equality test on strings_). In most situations, CodeQL would probably be correct, but in this specific context it is wrong: if the new value _is the same identical object as_ the existing one, then there is no need to instantiate a brand new object. It would not be correct to use a simple `equals` check, for reasons left to the reader to ponder. CodeQL will also flag `@With` usages on other reference types with [_Reference equality test of boxed types_](https://codeql.github.com/codeql-query-help/java/java-reference-equality-of-boxed-types/), for example if you add `@With` to a `Long` or `Integer` field.

This action also ensures (only for Maven projects right now) that the classpath is set so that delombok can correctly process files that use `@Delegate`. Without the classpath, delombok will not be able to process files containing `@Delegate` because it won't know anything about the target class and thus won't know what methods to implement.

## Configuration Options

You can configure several inputs:

* `directory`: The path to the workspace directory (defaults to `github.workspace`)
* `sourcePath`: Path relative to workspace directory where source files are (defaults to `src`)
* `printDelombokSource`: Whether to print the delomboked source files (`true` or `false`, defaults to `false`)

Here is an example using all three options:

```yaml
    # Delombok before building code
    - name: Delombok
      uses: sleberknight/delombok-action@v0.7.0
      with:
        directory: /data/src/workspace/my_service
        sourcePath: code/java/src
        printDelombokSource: true
```
