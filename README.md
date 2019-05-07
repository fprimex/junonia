# Junonia

[A snail with a beautiful shell.](https://en.wikipedia.org/wiki/Scaphella_junonia)

Document your shell program in Markdown and get:

* argument parsing, including
  - subcommands
  - positional parameters
  - options
  - booleans
  - ability to specify defaults
  - check for option name validity
  - check for boolean value validity
* environment variable configuration
* configuration file support
* configuration file management
* command line help generation

The junonia library also provides:

* help command output and other caching
* cache file function and command for management
* awk utility scripts for output, formatting, and more
* shell utility scripts for output, formatting, and more
* plugin support and management (still under development)

If the program implementation follows the junonia conventions for project layout, then all that is required, typically, is to write Markdown, then implement each subcommand as a shell function that will receive argument values in the order defined in the Markdown, and finally `junonia_bootstrap; . $JUNONIA_PATH/path/to/junonia; junonia_run "$@"`

## Conventional locations

All conventional, automatically discovered source paths, for an example project `prog` are outlined in the following two listings.

If `prog` is not being run from inside of a `bin` directory, then `JUNONIA_PATH` will be set to `/absolute/path/to/prog`. Then the following paths are searched for function implementations (`*.sh` files) and Markdown documentation (`*.md` files).

```
$JUNONIA_PATH/
  prog             # program that is run

  prog*.sh         # subcommand scripts such as prog_sub1.sh
  prog*.md         # documentation files such as prog_sub1.md

  cmd/prog*.sh
  cmds/prog*.md

  doc/prog*.md
  docs/prog*.md
```

If `prog` is executed from inside a `bin` directory (`project/bin/prog`), then `JUNONIA_PATH` is set to the absolute path to the directory containing the `bin` directory (`/absolute/path/to/project`). So the `JUNONIA_PATH` variable can be thought of as the path to the UNIX prefix. The earlier paths such as `cmd` are searched relative to `JUNONIA_PATH` as above, but typically if the program is in `bin` the intention is to lay out the project in a UNIX prefix.

```
$JUNONIA_PATH/
  bin/prog
  lib/prog/script*.sh
  usr/share/doc/prog/script*.md
```

## Examples layouts and invocation options

See the [examples](https://github.com/fprimex/junonia/tree/master/examples) directory to see how you can use Junonia to parse arguments from either a program argument spec defined in a tree-like format, or from Markdown documentation for each command.

## Junonia utilities and functions

### Shell

#### Junonia configuration

* `junonia_bootstrap`

Copy the minimal version of this function into the program's top level file. It is used to resolve symlinks and locate the absolute path to the top level file. From there, the junonia library can be sourced using `$JUNONIA_PATH` as an absolute path to the project.

* `junonia_init`

Configures the junonia library for use by setting a number of different variables.

```
JUNONIA_NAME       Name of script after resolving symlinks and removing .sh
JUNONIA_CAPNAME    Name in all caps
JUNONIA_CONFIG     Path to script rc file
JUNONIA_CONFIGDIR  Path to config directory
JUNONIA_CACHEDIR   Path to cache directory
JUNONIA_CACHE      Flag to optionally disable (0) caching
JUNONIA_INIT       Init guard to prevent attempted re-inits
JUNONIA_FS         Information separators
JUNONIA_GS
JUNONIA_RS
JUNONIA_US
JUNONIA_WRAP       Width of two column output (option help listings)
JUNONIA_COL1       Width of column one
JUNONIA_COL2       Width of column two
TMPDIR             Set if unset, always format with ending '/' removed
```

* `junonia_setdebug`

Calld by `junonia_init`. Configures if file descriptor 3 should be directed to file descriptor 2 (stderr) or `/dev/null`. Debug output (`echodebug`) is directed to FD3, so it will either be shown on FD2 or suppressed. Configure debugging by setting `JUNONIA_DEBUG` to 1 or 0.

#### Program invocation

* `junonia_run "$@"`

Resolve all arguments by searching conventional directories for Markdown documentation, generating a program argument spec, inspecting the program configuration file (e.g. `~/.prog/progrc` containing `PROG_option_one="value"`), inspecting environment variables (e.g. `PROG_option_one=value`), and command line arguments (e.g. `prog -option-one value`). With all arguments resolved, search the conventional directories for a function implementation, then execute the function with the arguments.

The function that is called will recieve a (possibly empty) value for each positional parameter and option in the order they are defined in the documentation. Therefore, the implementation of a function usually starts similar to the following:

```
prog_sub1 () {
  option_one="$1"
  foo="$2"
  bar="$3"

  # function continues ...
```

The values received may be multiline. Additionally, if the argument can be specified multiple times, then the values collected with each instance will be separated by the unit separator, which is provided in `JUNONIA_US` for convenience. To iterate over these values, manipulate the input field separator:

```
prog_sub1 () {
  multival_opt="$1"

  IFS=$JUNONIA_US
  for val in $multival_opt; do
    # need to unset (or restore, if a custom IFS was in use)
    # so subsequent operations in the loop behave as expected
    unset IFS

    # process val here ...

    # re-set to the unit separator for the next iteration
    IFS=$JUNONIA_US
  done

  # finally, unset IFS to continue normally
  unset IFS

  # function continues ...
```

* `junonia_runmd "$md_dir_file_or_str" "$@"`
* `junonia_runmd_filtered "$filter_func_name" "$md_dir_file_or_str" "$@"`
* `junonia_runspec "$spec" "$@"`
* `junonia_runspec_filtered "$filter_func_name" "$spec" "$@"`

The above `junonia_run*` functions are similar to `junonia_run`, except that a Markdown directory, file, or string is provided rather than searched for, and a filter function can be explicitly specified. The `spec` version is a more advanced version that skips the Markdown documentation and directly implements the program argument spec rather than parsing Markdown into the program argument spec. If a `runspec` function is used, then `help` will print the spec rather than any Markdown based documentation.

#### Program management of junonia features 

* `junonia_update_config "$config_file VAR [VAR ...]`

Manages shell files containing environment variables. Use `VAR` to add, update, or remove entries. If `VAR` is given as `NAME=VALUE`, then `NAME` will be added or update. Use `NAME=` or just `NAME` to remove the entry from the file.

* `junonia_cache_file "$cachepath" "$contents"`

Write or overwrite a file in the program cache directory with the given contents. The cache path should be provided as a relative path, as it will be placed in the cache path automatically. For example: `my_cache_dir/my_cache_file`. This is used internally to cache help output and the generated program argument spec.

#### IO

* `echoerr_raw "$msg"`
* `echoerr "$msg"`

Print to stderr. Raw prints the value exactly as given, whereas the non-raw version prepends the string `[ERROR]`.

* `echodebug_raw "$msg"`
* `echodebug "$msg"`

Print to file descriptor 3, which may be configured to direct to `/dev/null` (debugging is off) or stderr (debugging is on). Raw prints the value exactly as given, whereas the non-raw version prepends the string `[DEBUG]`.

* `echov "$msg"`

Convenience function that checks the variable `$verbose` to see if it should print the given message. The `$verbose` variable is not set or manipulated anywhere in junonia.

* `junonia_hardwrap "$lines" "$width" "$prefix" "$float"`

Wrap long lines to a specified width and optionally add a prefix / indent. Float determines if text without spaces longer than width should be allowed to run beyond the width instead of breaking on a non-space.

* `junonia_twocol "$t1" "$t2" "$c1" "$c2" "$g" "$p" "$f1" "$f2"`

Given two strings and specifications for two columns, format the text side by side in two columns.

```
t1  Text to go into the first column
t2  Text to go into the second column
c1  Width of column one
c2  Width of column two
g   Text to go in between the columns
p   Text to go in front of the complete text, like an indent
f1  If unbroken lines of t1 longer than col1 should be left unbroken
f2  If unbroken lines of t2 longer than col2 should be left unbroken
```

* `junonia_ncol "$t" "$c" "$g" "$p" "$f"`

Given n strings and specifications for n columns, format the text side by side in n columns. Since Bourne shell has no arrays, use `JUNONIA_FS` to separate the array entries. They will be split and handled by AWK.

```
t  Array of text to go into the columns
c  Array of column widths
g  Array of text to go between the columns
p  Text to go in front of the complete text, like an indent
f  If unbroken lines longer than cols should be left unbroken
```

* `junonia_randomish_int [$n]`

This convenience function is a POSIX way of getting some random digits. It is so-called 'randomish' because it is NOT CRYPTOGRAPHICALLY SOUND and SHOULD NOT BE USED FOR CRYPTOGRAPHIC PURPOSES. It does, however, produce things that are random enough for temporary file names and the like.

The seed HAS to be sufficient in order for this to work. Sending the current time, for example, is not usually sufficient unless using a nonstandard level of precision. See the shell wrapper for an example of a suitable seed.

A length can be given, which defaults to 10. The results always have leading zeroes stripped so that they are useful as decimal integer values.

* `junonia_require_cmds "$cmd1" [ "$cmd2" ... ]`

Simple function to iterate over a given list of command strings to ensure they can be found.
