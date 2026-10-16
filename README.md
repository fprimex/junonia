# Junonia

[A snail with a beautiful shell.](https://en.wikipedia.org/wiki/Scaphella_junonia)

Junonia is a shell framework for creating command line user interfaces from Markdown documentation. Command line argument parsing, help generation, and more are dynamically generated from definitions in Markdown files. Features include:

* argument parsing of
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

## Getting started

There are many different ways to use junonia to handle program configuration and execution, but for this 'getting started' section I'll assume you want to use Markdown for command and subcommand documentation, and use a directory layout that will be automatically discovered.

First, choose a directory layout that will, by convention, allow junonia to automatically discover documentation and function declarations. One of the following is recommended.

```
prog/
  prog
  cmd/
  doc/
```

```
prog/
  bin/prog
  lib/prog/cmd/
  usr/share/doc/prog/
```

The `prog` file will be the top level program. It must not end with `.sh`. Markdown documents go in the `doc` and `usr/share/doc/prog`  directory, and function implementations go in the `cmd` and `lib/prog/cmd` directory. Markdown documentation and functions follow a conventional format of `prog.md`, `prog_sub1.md`, `prog_sub1_sub11.md` for documenting the commands `prog`, `prog sub1`, and `prog sub1 sub11`. Similarly, function implementations are documented as `prog_sub1.sh` and `prog_sub1_sub11.sh`. The function implementation for `prog` itself should be in the `prog` top level program file.

For the Markdown `prog.md` located in `doc` or `usr/share/doc/prog`:

```
## `prog`

Short description of `prog`.

### Synopsis

    prog [SUBCOMMAND] [OPTIONS]

### Description

Long description of `prog`.

### Options

* `-shared-arg SHARED`

This option is available to all `prog` subcommands.
```

And the Markdown `prog_sub1.md` located in `doc` or `usr/share/doc/prog`:

```

## `prog sub1`

Short description of `sub1`.

### Synopsis

    prog sub1 [OPTIONS]

### Description

Description of subcommand number one.

### Options

* `-sub1-opt1 OPT1`

This is option one for subcommand one.
```

And the program `prog` in the root of the project or in the `bin` directory:

```
#!/bin/sh

# Version supplied to `prog version` command. If you wish for `-v` and such to
# also return the version, then those flags need to be implemented in the
# `prog` documentation and command. I wanted for `-v` and so forth to be
# available for other uses if desired.
prog_version () {
  echo "1.0.0"
}

# What is run when 'prog' or 'prog -shared-arg foo' is executed.
prog () {
  echo "-shared-arg: $1"
}

# A copy of junonia_boostrap goes here
# https://github.com/fprimex/junonia/blob/master/junonia_bootstrap

# During development you most likely want to disable the caching of help output
# and other items.
JUNONIA_CACHE=0

# Bootstrap resolves all symlinks and find the directory where all of the
# program documentation and function implementations live. For both directory
# layouts it results in the root directory. So for the first the directory
# containing 'prog', and for the second the directory containing 'bin'.
junonia_bootstrap
. "$JUNONIA_PATH/some/path/to/junonia"

# Resolve all arguments and execute the specified function with the set
# configuration file values, environment variable values, and command line
# arguments.
junonia_run "$@"
```

And the subcommand implementation `prog_sub1.sh` in `cmd` or `lib/prog/cmd`:

```
# What is executed with the following invocations:
# prog sub1
# prog sub1 -shared-arg foo -sub1-opt1 bar
# prog sub1 -sub1-opt1 bar

prog_sub1 () {
  echo "-shared-arg: $1"
  echo "-sub1-opt1:  $2"
}
```

The following is now available:

```
$ ./prog help
NAME
  prog -- Short description of `prog`.

SYNOPSIS
  prog [SUBCOMMAND] [OPTIONS]

DESCRIPTION
  Long description of `prog`.

OPTIONS
  -shared-arg SHARED
                  This option is available to all `prog` subcommands.

SUBCOMMANDS
  sub1            Short description of `sub1`.
  help            Print information about program and subcommand usage
  config          Display or edit the `prog` config file
  cache           Generate or clear meta-information cache
  plugin          Manage prog shell plugins and programs
  version         Display program version
```

```
$ ./prog -shared-arg foo
shared arg: foo
```

```
$ ./prog help sub1
NAME
  prog sub1 -- Short description of `sub1`.

SYNOPSIS
  prog sub1 [OPTIONS]

DESCRIPTION
  Description of subcommand number one.

OPTIONS
  -sub1-opt1 OPT1 This is option one for subcommand one.
```

```
$ ./prog sub1 -shared-arg foo -sub1-opt1 bar
shared arg: foo
sub1 opt1:  bar
```

And much more!

## Markdown notes and features

* The `command` and `command subcommand` must be at the h2 level, `##`.
* The `command` and `command subcommand` must contain the whole command, starting from the top level command. That is: `command subcommand subcommand` is correct. `subcommand subcommand` is not correct.
* Subcommands can have aliases: `command subcommand, subcommand_alias`. The definitive name for the subcommand, for documentation and implementation, is `subcommand`.
* Sections of the documentation can be skipped if, for example, there are no positional parameters. For the sections used, the following headers must be at the h3 level, `###`, and be exactly as follows:

```
### Synopsis
### Description
### Positional parameters
### Options
```

* Positional parameters are documented as:

```
### Positional parameters

* `PARAM1`

The description for `PARAM1`, to be supplied as, e.g., `prog param_value ...`.

* `PARAM2=param2_default

The description for `PARAM2`, which has a default value if it is omitted.
```

* Positional parameter meta-variables must be in all caps.
* All subcommands and positional parameters must come before all options.
* Options are documented as:

```
### Options

* `-option-one ONE`

An option that takes an argument.

* `-option-two TWO=2`

An option that takes an argument and has a default value.

* `-o, -option-three THREE`

An option that has an alias, `-o`. The definitive name of the option is the last one given, `-option-three` in this case.

* `-boolean-option-one`

A flag, or boolean option. It must not have a meta-variable. All flags default to a false value. This is 0 or false at the command line, and represented as a null value in shell code (e.g. `flag=`).

* `-boolean-option-two=1`

A flag, or boolean option, that is defaulting to true. All booleans are normalized to where in the shell code 1 is supplied for true, and the null value, or empty string, is supplied as false.

* `-multi-option ONE [-multi-option TWO ...]`

This format specifies that `-multi-option` can be given more than once on the command line, and all of the values will be collected. The values are separated by `JUNONIA_US`, the unit separator, so that newlines and spaces can be preserved when iterating over the supplied values. See [Program invocation](#program-invocation) for an example of iterating over a multi-option value using `IFS` and `JUNONIA_US`.
```

* Documenting subcommands in Markdown is encouraged, but not required for functionality. During command execution, subcommands are discovered dynamically both for command execution and for online documentation.

## JSON options

An option whose name begins with a period is a field of a JSON body rather than an argument. Junonia collects these into a JSON document, which is what gets sent as the payload of a `POST`, `PUT`, or `PATCH` request by the web layer in `junonia_web`, where a command documents its endpoint with a `### REST endpoint` section. Whatever is built is also available to the command function as `JW_JSON`.

```
* `.name NAME`

A JSON string.

* `.enabled=true`

A JSON boolean defaulting to true.

* `.disabled=0`

A JSON boolean defaulting to false.
```

The rules for these are the same as for other options, with two differences that matter.

A boolean with a documented default appears in the JSON whatever that default is, false included, so that the key exists in the body. A boolean with no documented default is left out until it is given, because in a `PATCH` payload an absent field means leave alone, and junonia should not invent an opinion the caller never expressed. So document a default of false for a field the API must be told is false, and document no default for a field that should go unsent unless the user asks.

JSON options are not passed to the command function and take up no argument slot, so the positions of the arguments a function receives are unaffected by how many JSON options are documented or given.

Their names need not be documented. junonia collects every JSON option it is given, because what an API call accepts as a payload is rarely something a manual can enumerate, and never reports an undocumented one as an unknown option. What documenting one does is give it a default, which also puts a boolean into every body, true or false; an undocumented name, like a documented one with no default, appears only when given.

The word is the key. Everything of the name after the leading period becomes a key of the body, quoted as jq requires, so `.x=1 bob` sends `{"x=1":"bob"}` and `.a.b 1` sends `{"a":{"b":1}}` — a period nests, and dashes, equals signs and spaces (with the usual shell quoting) are simply the key. Appending `[]` to a name adds each value to an array instead of replacing the last, so `.tags[] x .tags[] y` sends `{"tags":["x","y"]}`.

That trailing `[]` is the only syntax in a name. It is what makes a key whose own name ends in `[]` unsettable, so `{"tags":["a","b"]}` can be asked for and `{"tags[]":["a","b"]}` cannot, valid JSON though it is. Brackets anywhere else are part of the key: `.tag[]s x` sends `{"tag[]s":"x"}`, `.a[0].b v` sends `{"a[0]":{"b":"v"}}`, and a trailing pair on such a name appends as it would on any other, so `.tag[]s[] x .tag[]s[] y` sends `{"tag[]s":["x","y"]}`.

Values may come from the command line (`.name bob`, `.enabled false`), from a configuration file entry, or from the environment variable, in the same precedence order as any other option, and a value given on the command line beats a documented default of either sign.

## Function notes and features

* Functions implementations are searched for by the format `command_subcommand` for the invocation 'command subcommand'.
* If the command is already present then that command is used. So, for example, all commands could be implemented in the top level program, or they could be implemented in any file or using any method as long as they are sourced or otherwise present at execution time.
* Functions receive argument values in the order they are declared in the documentation. This includes arguments of preceding commands. So if `command` has argument `-option-one`, and `subcommand` has `-option-two`, then executing `command subcommand` will cause the `command_subcommand` function to receive the value of `-option-one` as `$1` and `-option-two` as `$2`.
* The argument value handling implemented in junonia allows for spaces and multi-line arguments to be given and properly passed to the function. This is accomplished by separating argument values that are given with `JUNONIA_RS`, the record separator, and then passing the values with `IFS` set to `JUNONIA_RS`. This is an implementation detail, and no end-user use of `JUNONIA_RS` is needed. Just be aware that your values can contain spaces and newlines and junonia will handle this properly.
* Multi-value options, as mentioned, will be separated with `JUNONIA_US`, the unit separator. See [Program invocation](#program-invocation) for an example of iterating over a multi-option value using `IFS` and `JUNONIA_US`.
* It is not recommended to implement the top level function as, e.g., `prog.sh` in the commands directory. This is because when the search for the `prog` command is done, the top level script itself will be found. Instead, implement the `prog` function in the top level script and junonia will detect that it is a shell function properly.
* A command should not have both positional parameters and subcommands. Positional parameters are resolved before subcommands, so a value that happens to name a subcommand is taken for the positional parameter, and the options of that subcommand are then reported as unknown. For example, document `prog opts [POS1]` or `prog opts SUBCOMMAND`, but not both.
* All positional parameters must precede all options, and options must follow the complete subcommand path. `prog sub -shared-foo one -opt two` is valid; `prog -shared-foo one sub -opt two` is not.
* An option and its value are separate words. The `prog -foo-bar=value` form is not accepted; use `prog -foo-bar value`. A JSON option is named by one whole word, so `prog json .foo-bar=value` is the key `foo-bar=value` set to true, and its value, if any, is the next word.

## Configuration file and environment variables

Each option name has a corresponding environment variable name and configuration file entry. The name used for both is the same. The program name is capitalized, followed by `_`, then the option name with its hyphens converted to `_` as well, and the two are concatenated, resulting in `PROG_foo_bar`.

A subcommand's options are prefixed with the whole command path, and only the program name is capitalized. The option `-foo-bar` of the command `prog sub` is set by `PROG_sub_foo_bar`, and of `prog sub deeper` by `PROG_sub_deeper_foo_bar`. Note that this means the names of subcommands are case sensitive in the configuration file and environment.

The default configuration file location is `~/.prog/progrc`. The file is processed as a shell file in such a way that only `PROG_` variable values are set. However, since the file is sourced, THE CONFIGURATION FILE CAN EXECUTE COMMANDS. This is not a recommended use of the configuration file. Additionally, the configuration file can be manipulated with the `config` subcommand. Be aware that the `config` subcommand currently cannot handle removing multi-line values, and those need to be manually removed.

Similarly, the environment variable `PROG_foo_bar` can be set to a value to supply a value to an invocation of `prog`.


## Argument value resolution

Junonia provides several options for obtaining function argument values. They are, in order of lowest to highest precedence:

* Implied default (blank)
* Markdown default (`-foo-bar BAZ=1`)
* Configuration file (As a line in `~/.prog/progrc`: `PROG_foo_bar=2`)
* Environment variable (exported in the environment: `PROG_foo_bar=3`)
* Command line argument (`prog -foo-bar 4`)

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

## Additonal examples layouts and invocation options

See the [examples](https://github.com/fprimex/junonia/tree/master/examples) directory to see how you can use junonia to parse arguments from either a program argument spec defined in a tree-like format, or from Markdown documentation for each command.

## Testing

Run the smoke tests with:

```
$ test/smoke.sh
```

The suite runs the examples above, then builds a program in a scratch directory and asserts on the exact argument list its command functions receive for every kind of argument: spec defaults, configuration file, environment variables, command line values, booleans, repeatable options, positional parameters, nested subcommands, and the error paths. It also exercises caching and the `config` subcommand. Nothing outside the scratch directory is touched.

Pass `-v` for the output of each failing check, and set `JUNONIA_SMOKE_KEEP=1` to leave the scratch directory in place for inspection. The suite is run against the BSD, GNU, and mawk AWK implementations; put whichever `awk` you want to exercise first in `PATH`.

## Locale

`junonia_init` exports `LC_COLLATE=C`. Documentation file names encode the command tree (`prog_sub1_sub11.md`), so both the argument spec and the help output are built by walking the documentation in a collation where `_` sorts after `.` and the parent of a command tree is always read before its children. The default collation of many systems does not order them that way, which results in a spec in which subcommands appear before the commands that hold them. The value is exported, so it also applies to any program junonia runs on your behalf. Set it back after sourcing junonia if your own program depends on a different collation.

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

* `echov   "$msg"`
* `echovv  "$msg"`
* `echovvv "$msg"`

Convenience functions that check the variable `$verbose`, `$vverbose`, and `$vvverbose` to see if it should print the given message. The environment variables are not set or manipulated anywhere in junonia.

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

* `junonia_is_int $n`

Determine if the given argument is an integer value.

* `junonia_is_num $n`

Determine if the given argument is any kind of numeric value.

* `junonia_require_cmds "$cmd1" [ "$cmd2" ... ]`

Simple function to iterate over a given list of command strings to ensure they can be found.

# `junonia_envvars a|r|w [PREFIX]`

Get all environment variables, all readonly environment variables, or all writable environment variables matching an optional prefix.

### AWK

Similar to the shell utility functions, there are several AWK functions available as shell variables. All functions are available in a single environment variable `JUNONIA_AWKS`, declared as:

```
readonly JUNONIA_AWKS="
$junonia_awk_hardwrap_line
$junonia_awk_hardwrap
$junonia_awk_twocol
$junonia_awk_ncol
$junonia_awk_echoerr
$junonia_awk_echoerr_raw
$junonia_awk_echodebug
$junonia_awk_echodebug_raw
$junonia_awk_randomish_int
"
```

The function specs are the following:

```
echoerr(msg)
echoerr_raw(msg)
echodebug(msg)
echodebug_raw(msg)
randomish_int(seed, n)

hardwrap_line(line, width, pre, float)
hardwrap(lines, width, pre, float)
twocol(text1, text2, col1, col2, gutter, pre, float1, float2)
ncol(n, texts, cols, gutters, pre, floats)
```

These functions match (and are the implementations for) the shell functions. To use these AWK functions in your own AWK programs, I suggest a format such as the following:

```
  awk_prog='
    BEGIN {
      line = "A line to wrap on spaces at width, then indent by pre"
      print hardwrap(line, 15, "  ")
    }'
  awk "$JUNONIA_AWKS $awk_prog"
```

Giving the result:

```
  A line to wrap
  on spaces at
  width, then
  indent by pre
```

