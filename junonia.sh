###
### Typical usage and program flow
###

# In the top level, user script:
# run its own copy of junonia_bootstrap to set JUNONIA_TARGET and JUNONIA_PATH
# . "$JUNONIA_PATH/some/path/to/junonia.sh to source junonia
# junonia_run, the main entrypoint that runs auto-discovery
#
# Then, in junonia.sh the following is run:
# junonia_init to set up the environment
# junonia_run_* function chosen based on auto-discovery
#   possibly _junonia_md2spec to generate spec from md files
#   _junonia_run_final to collect all of the run options and start execution
#     _junonia_set_args to determine arg values from:
#                       spec defaults, config file, env vars, and cli args
#     _junonia_exec to receive all arg values and run the function
#       possibly run help and exit
#       possibly run a user filter function to preprocess args
#       run the specified function with the fully resolved arguments


###
### Globals
###

# Intended to be user configurable / changed at any time

JUNONIA_WRAP=78
JUNONIA_COL1=18
JUNONIA_COL2=60

# Intended to not be changed.

# Information Separator control characters (IS4 - IS1)
readonly JUNONIA_FS="" # File   Separator (FS / IS4 / dec 28)
readonly JUNONIA_GS="" # Group  Separator (GS / IS3 / dec 29)
readonly JUNONIA_RS="" # Record Separator (RS / IS2 / dec 30)
readonly JUNONIA_US="" # Unit   Separator (US / IS1 / dec 31)

# Variables set by junonia_bootstrap:
# JUNONIA_TARGET  Absolute path to the script
# JUNONIA_PATH    Absolute path to the directory containing the script

# Variables set by  junonia_init:
# JUNONIA_NAME    Name of the script after resolving symlinks and removing .sh
# JUNONIA_CAPNAME Name in all caps
# JUNONIA_CONFIG  Path to script rc file
# JUNONIA_INIT    Init guard to prevent attempted re-inits
# TMPDIR          Set if unset, consistently formatted with ending '/' removed

# This variable is used / checked, but is not set by junonia itself.
# JUNONIA_DEBUG   Whether or not to show output on stderr from echodebug (FD3)


###
### Copy of the bootstrap function
###
### For a compact version of this script to copy into your own script, see
### junonia_bootstrap.sh
###

# This function can be copied to the top level script to set absolute paths to
# the script. From there, junonia.sh, other shell libraries, and other assets
# can be loaded or referenced. For example, for a project with directories like
# the following:

# /home/user/foo/code/project.git/script
# /home/user/foo/code/project.git/lib/junonia.sh

# the following code could be used in script:

#   # copied from junonia.sh
#   junonia_bootstrap () {
#     ...
#   }
#
#   junonia_bootstrap
#   . "$JUNONIA_PATH/lib/junonia.sh"
#
#   # continue using junonia functions like junonia_run, echoerr, etc...

# Note one oddity: in order to keep the global variable namespace unpolluted,
# the JUNONIA_PATH variable is used to hold the value of the symbolic link path
# until it is finally set to the absolute path to the directory containing the
# script. In this way only the variables ultimately set, JUNONIA_TARGET and
# JUNONIA_PATH, are created / used.

# Determine the script location. With the exception of the function name and
# globals set, this is generic and does not rely on anything specific to the
# rest of junonia. Use this in any script and the following will be set:
#
# JUNONIA_TARGET Absolute path to script being run with symlinks resolved.
# JUNONIA_PATH   Absolute path to directory containing script being run.
junonia_bootstrap () {
  # Get the command used to start this script
  JUNONIA_TARGET="$0"

  # If executing via a series of symlinks, resolve them all the way back to the
  # script itself. Some danger here of infinitely cycling.
  while [ -h "$JUNONIA_TARGET" ]; do

    # Begin usage of JUNONIA_PATH to hold the link path.

    # Look at what this link points to
    JUNONIA_PATH="$(file -h "$JUNONIA_TARGET" | \
                    sed 's/^.*symbolic link to //')"

    if [ "$(echo "$JUNONIA_PATH" | cut -c -1)" = "/" ]; then
      # Link path is absolute (first character is /); just need to follow it.
      JUNONIA_TARGET="$JUNONIA_PATH"
    else
      # Link path is relative, need to relatively follow it.
      # e.g. running `./foo` and link is to `../../bar`
      # Go look at ./../../bar
      JUNONIA_TARGET="$(dirname $JUNONIA_TARGET)"
      JUNONIA_TARGET="$JUNONIA_TARGET/$JUNONIA_PATH"
    fi

    # End usage of JUNONIA_PATH to hold the link path.

  done

  # Now TARGET should be like the following, where 'script' is not a symlink:
  # /some/path/to/the/actual/script
  # or
  # ./../some/path/to/the/actual/script
  #
  # Set absolute paths for TARGET and PATH
  # PATH   /home/user/code/project/name/bin
  # TARGET /home/user/code/project/name/bin/script
  readonly JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
  readonly JUNONIA_TARGET="$JUNONIA_PATH/$(basename $JUNONIA_TARGET)"
}


###
### I/O helpers
###

# Print messages to stderr. Use printf to ensure the message is verbatim.
# e.g. do not interpret \n in JSON.
echoerr_raw () { printf '%s\n' "$@" 1>&2; }
echoerr () { echoerr_raw "[ERROR] $@"; }

# Print debug messages to file descriptor 3, which will either go to stderr if
# debug output is enabled or /dev/null if it is not.
echodebug_raw () { printf '%s\n' "$@" 1>&3; }
echodebug () { echodebug_raw "[DEBUG] $@"; }


###
### AWK utility functions
###

# Convenience functions for error and debug output
_awk_echoerr='function echoerr(msg) {
  printf "[ERROR] %s\n", msg >"/dev/stderr"
}'

_awk_echoerr_raw='function echoerr_raw(msg) {
  printf "%s\n", msg >"/dev/stderr"
}'

_awk_echodebug='function echodebug(msg) {
  if(JUNONIA_DEBUG) {
    echoerr_raw("[DEBUG] " msg)
  }
}'

_awk_echodebug_raw='function echodebug_raw(msg) {
  if(JUNONIA_DEBUG) {
    echoerr_raw(msg)
  }
}'

_awk_hardwrap='
  # Wrap a long line to a specified width and optionally add a prefix / indent.
  #
  # Arguments
  # ---------
  # line    Text to wrap
  # width   Line width to wrap to
  # pre     Prefix string such as an indent
  #
  # Locals
  # ------
  # str     Portion of the line being wrapped
  # n       Index of the next space in the line
  # wrapped Final wrapped result
  function hardwrap(line, width, pre,
                    str, n, wrapped) {

    # The start of the line will be removed as it is wrapped, so continue
    # producing wrapped lines as long as line is longer than the wrap width.
    while(length(line) > width) {

      # Need to deal with lines that have no spaces and cannot be wrapped.
      n = index(line, " ")
      if(n == 0) {
        break
      }

      if(n > width) {
        # The next space is beyond the wrap, so wrap on that space.
        str = substr(line, 1, n - 1)
      } else {
        # The next space is within the wrap width, so take a chunk of the line
        # that is the length of the wrap width.
        str = substr(line, 1, width)
      }

      # Remove everything at the end of the string that is the last space
      # followed by not a space.
      sub(/ [^ ]*$/, "", str)

      # Strip leading space from the chunk so it will be aligned.
      sub(/^ /, "", str)

      # Add this wrapped line to the hardwrapped result.
      wrapped = wrapped pre str "\n"

      # Removed the portion that was just wrapped from the line for continued
      # processing.
      line = substr(line, length(str) + 2, length(line))
    }

    # There probably is a bit of text that is leftover. It needs to be aligned
    # and added to the wrapped result.
    if(line) {
      sub(/^ */, "", line)
      wrapped = wrapped pre line "\n"
    }

    # Send back the hardwrapped string with the final newline removed.
    return substr(wrapped, 1, length(wrapped) - 1)
  }
'

_awk_twocol='
  # Given two strings and specifications for two columns, format the text side
  # by side in two columns.
  #
  # Arguments
  # ---------
  # text1     Text to go into the first column
  # text2     Text to go into the second column
  # col1      Width of column one
  # col2      Width of column two
  # gutter    Text to go in between the columns
  # pre       Text to go in front of the complete text, like an indent
  #
  # Locals
  # ------
  # fmt       Print format for each wrapped and combined line
  # text1a    Array of lines in text1
  # text2a    Array of lines in text2
  # i         Iterator variable
  # formatted Final result
  function twocol(text1, text2, col1, col2, gutter, pre,
                  fmt, text1a, text2a, i, formatted) {
    # Wrap each line to the desired column width.
    text1 = hardwrap(text1, col1)
    text2 = hardwrap(text2, col2)

    # Assemble the print format. e.g.
    # Prefix 2 spaces, col1 20, gutter 1 space, col2 40
    # "  %-20s %-40s"
    fmt = pre "%-" col1 "s" gutter "%-" col2 "s"

    # Put each line of each hardwrapped column in arrays
    split(text1, text1a, "\n")
    split(text2, text2a, "\n")

    # Iterate over the arrays and put the lines next to each other using the
    # assembled format.
    i = 1
    while(text1a[i] || text2a[i]) {
      formatted = formatted sprintf(fmt, text1a[i], text2a[i]) "\n"
      i++
    }

    # Send back the final, two column formatted text with the final newline
    # removed.
    return substr(formatted, 1, length(formatted) - 1)
  }
'

# This convenience function is a POSIX way of getting some random digits. It is
# so-called 'randomish' because it is NOT CRYPTOGRAPHICALLY SOUND and SHOULD
# NOT BE USED FOR CRYPTOGRAPHIC PURPOSES. It does, however, produce things that
# are random enough for temporary file names and the like.
#
# The seed HAS to be sufficient in order for this to work. Sending the current
# time, for example, is not usually sufficient. See the shell wrapper for an
# example of a suitable seed.
_awk_randomish_int='
  function randomish_int(s, n) {
    # A seed has to be given
    if(! s) {
      exit 1
    }

    # Default to 10 digits
    if(! n) {
      n=10
    }

    # As mentioned above, the seed given here needs to be suitable.
    srand(s)

    # Initial accumulation. String leading zeros from this one so the result
    # is useful as an integer.
    r = rand()
    sub(/0\.0*/, "", r)

    # Build up enough digits, then take the first n of them.
    while(length(r) < n) {
      r = r rand()
      sub(/0\./, "", r)
    }
    return substr(r, 1, n)
  }
'

readonly JUNONIA_AWKS="
$_awk_hardwrap
$_awk_twocol
$_awk_echoerr
$_awk_echoerr_raw
$_awk_echodebug
$_awk_echodebug_raw
$_awk_randomish_int
"


###
### Shell utility functions
###

# Shell version of _awk_randomish_int. See its documentation for VERY important
# information on appropriate usage. With no argument provided it uses the
# default in the awk function.
randomish_int () {
  awk_prog='BEGIN { printf "%s", randomish_int(s, n) }'

  # Provide a seed to awk's srand that is the process ID of a new sh process.
  if ! awk -v s="$(/bin/sh -c 'echo $$')" \
           -v n="$1" "$_awk_randomish_int $awk_prog"; then
    echoerr 'unable to generate random int'
    return 1
  fi
}


###
### Configuration file management
###

# Add, remove, or modify given values in a shell config file at the given path.
# Remove values by providing an empty value. If no file exists it will be
# created.
#
# junonia_update_config FILEPATH VAR [VAR ...]
#
# Where VAR is NAME=VALUE to set the value and NAME= or NAME to remove the
# value.
junonia_update_config () {
    if [ -f "$1" ]; then
        echodebug "[DEBUG] Modifying $1"
    else
        echodebug "[DEBUG] Creating $1"
        if ! touch "$1"; then
            echoerr "ERROR: Could not create $1"
            return 1
        fi
    fi

    if ! config="$(awk '# Generate the config from arg input and existing file.

        # Given a potential var=value line, separate them, set VARNAME
        # and VARVALUE.
        function splitvar(var) {
            # Find = or the end
            eq = index(var, "=")
            if(eq == 0) {
                eq = length(var + 1)
            }

            # Extract the name and value
            VARNAME = substr(var, 1, eq - 1)
            VARVALUE = substr(var, eq + 1)

            # Enclose the value in quotes if not already
            if(VARVALUE && VARVALUE !~ /^".*"$/) {
                VARVALUE = "\"" VARVALUE "\""
            }

            # Error if VARNAME is not a valid shell variable name
            if(VARNAME !~ varname_re) {
                VARNAME=""
                VARVALUE=""
                return 1
            }
            return 0
        }

        BEGIN {
            # Matches valid shell variable names
            varname_re = "[A-Za-z_][A-Za-z0-9_]*"

            # Arg1 is the config file. The rest are config entries to process,
            # so make them into an array and remove them from the arg vector.
            for(i=2; i<ARGC; i++) {
                if(splitvar(ARGV[i]) == 0) {
                    config[VARNAME] = VARVALUE
                    ARGV[i] = ""
                    vars++
                }
            }

            # No variables were given to process.
            if(!vars) {
                exit 1
            }

            ARGC = 2
        }

        # Start processing the config file.

        # This line is a variable we were given to modify.
        $0 ~ "^" varname_re && splitvar($0) == 0 && config[VARNAME] {
            # If no value was supplied, skip it, effectively removing it from
            # the config file.
            if(! config[VARNAME]) {
                next
            }

            # There is a value, so write that and remove it from the array
            # since it was processed.
            print VARNAME "=" config[VARNAME]
            delete config[VARNAME]
            next
        }

        # Preserve unmodified lines as-is.
        { print }

        END {
            # If there are still config entries that means we were given
            # variables to process that were not already in the config file.
            # Those should then be added at the end.
            for(c in config) {
                if(config[c]) {
                    print c "=" config[c]
                }
            }
        }
    ' "$@")"; then
        echoerr "Error processing configuration"
        echoerr "$config"
        return 1
    fi

    if ! echo "$config" | tee "$1"; then
        echoerr "Error writing configuration to file $1"
        echoerr "$config"
        return 1
    fi
}


###
### Markdown parsing functions
###

# Parse Markdown text into a program argument spec
_junonia_md2spec () {
  awk '
    # Print the currently stored spec and reset for the next one.
    function spec () {
      print indent cmd

      for(i=1; i<=n_params; i++) {
        print indent "  " params[i]
      }

      for(i=1; i<=n_opts; i++) {
        print indent "  " opts[i]
      }

      indent = ""
      cmd = ""
      n_params = 0
      n_opts = 0
      split("", params, ":")
      split("", opts, ":")
    }

    # When encountering a header, leave any header we were in.
    /^#/ {
      synopsis = 0
      positional = 0
      options = 0
    }

    # Top level "##" header
    # ## `command subcommand`
    /^## `[-_A-Za-z0-9 ]+`/ {
      if(cmd) {
        spec()
      }

      for(i=0; i<NF-2; i++) {
        indent = indent "  "
      }

      gsub(/`/, "")
      cmd = $NF
    }

    /^### Positional parameters/ {
      positional = 1
    }

    # * `POS_ONE`
    # * `POS_TWO=default`
    positional && /^\* `[-_A-Z0-9]+`/ {
      gsub(/^\* `|`$/, "")
      split($0, a, "=")
      params[++n_params] = a[1]
      if(a[2]) {
        param_defs = a[2]
      }
    }

    /^### Options/ {
      options = 1
    }

    # * `-option`
    # * `-option=bool_default`
    # * `-option VAL`
    # * `-option VAL=default`
    # * `-option VAL1 [-option VAL2 ...]`
    # * `-option NAME=VALUE [-option NAME=VALUE ...]`
    options && /^\* `-[-A-Za-z0-9]+/ {
      gsub(/^\* `|`$/, "")

      if(NF > 2) {
        # Defaults are not allowed for multi-opts
        opts[++n_opts] = $1 " [" $2 "]"
      } else {
        split($1, a, "=")
        opt = a[1]
        bool_default = a[2]

        if(bool_default) {
          opts[++n_opts] = opt "=" bool_default
        } else {
          sub("^ *" opt " *", "")
          split($0, a, "=")
          meta = a[1]
          opt_default = a[2]

          if(meta) {
            if(opt_default) {
              opts[++n_opts] = opt " " meta "=" opt_default
            } else {
              opts[++n_opts] = opt " " meta
            }
          } else {
            opts[++n_opts] = opt
          }
        }
      }
    }

    END {
      spec()
    }
  ' "$@"
}

# Parse Markdown text into command line help
_junonia_md2help () {
  awk_prog='
    BEGIN {
      col1_indent = sprintf("%" col1 "s", "")
      cmd_re = "^" cmd "$"
      subcmd_re = "^" cmd " [-_A-Za-z0-9]+$"
      h2 = 0
      txt = "NAME\n"
    }

    # When encountering a header, leave any header we were in.
    /^#/ {
      if(intro + synopsis + description + positional) {
        txt = txt "\n"
      }

      intro = 0
      synopsis = 0
      description = 0
      positional = 0
      options = 0
      subcmd = ""
    }

    # Top level "##" header
    # ## `command subcommand`
    /^## / {
      gsub(/^## `|`$/, "")
    }

    $0 ~ cmd_re {
      h2++
      txt = txt "  " $0
      intro = 1
      next
    }

    $0 ~ subcmd_re {
      h2++
      if(h2 == 2) {
        txt = txt "SUBCOMMANDS\n"
      }
      subcmd = $NF
      next
    }

    intro && h2 == 1 && ! /^$/ {
      txt = txt " -- " $0 "\n"
      next
    }

    subcmd && ! /^$/ {
      txt = txt twocol(subcmd, $0, col1 - 3, col2, " ", "  ") "\n"
      next
    }

    # Not seen the right command or have processed it already, so none of the
    # below processing should be done.
    h2 != 1 {
      next
    }

    /^### Synopsis/ {
      synopsis = 1
      txt = txt "SYNOPSIS\n"
      next
    }

    synopsis && /^    [a-z]/ {
      sub(/^    /, "  ")
      syn = $0
      txt = txt $0 "\n"
    }

    /^### Description/ {
      description = 1
      txt = txt "DESCRIPTION"
      next
    }

    description && ! /^$/ {
      txt = txt "\n" hardwrap($0, wrap - 2, "  ") "\n"
    }

    /^### Positional parameters/ {
      positional = 1
      txt = txt "PARAMETERS\n"
      next
    }

    #* `POS_ONE`
    positional && /^\* `[-_A-Z0-9]+`/ {
      gsub(/`/, "")
      param_col1 = $2
    }

    positional && /^[A-Za-z0-9]/ {
      txt = txt twocol(param_col1, $0, col1 - 3, col2, " ", "  ") "\n"
    }

    /^### Options/ {
      options = 1
      txt = txt "OPTIONS\n"
      next
    }

    #* `-option`
    #* `-option VAL`
    #* `-option VAL1 [-option1 VAL2 ...]`
    options && /^\* `-[-A-Za-z0-9]+/ {
      gsub(/^* |`/, "")
      opt_col1 = $0
    }

    options && /^[A-Za-z0-9]/ {
      if(length(opt_col1) > col1 - 3) {
        opt_col2 = hardwrap($0, wrap - col1, col1_indent)
        txt = txt "  " opt_col1 "\n" opt_col2 "\n\n"
      } else {
        txt = txt twocol(opt_col1, $0, col1 - 3, col2, " ", "  ") "\n\n"
      }
    }

    END {
      sub(/\n*$/, "", txt)
      print txt
    }
  '

  if [ -z "$1" ]; then
    echoerr "Command text required to generate help"
    return 1
  fi

  cat | awk -v wrap="$JUNONIA_WRAP" -v col1="$JUNONIA_COL1" \
            -v col2="$JUNONIA_COL2" -v cmd="$1" \
            "$JUNONIA_AWKS $awk_prog"
}


###
### Execution environment setup and management
###

# Configure the output level settings. Providing 0 or no argument disables
# output from echodebug. Providing 1 or any other non-empty value enables
# output from echodebug. This is accomplished by having echodebug output to
# file descriptor 3, and redirecting 3 to either /dev/null (disabled) or 2
# (stderr, enabled).
junonia_setdebug () {
  case "$1" in
    0|'')
      exec 3>/dev/null
      ;;
    1)
      exec 3>&2
      ;;
    *)
      echoerr "invalid log level: $1"
      echoerr "defaulting to 1"
      exec 3>&2
      ;;
  esac
}

# Configure the execution environment by setting global variables for names and
# paths. Additionally configure debugging and temporary storage.
junonia_init () {
  if [ -n "$JUNONIA_INIT" ]; then
    # init has already been run
    return
  fi

  # Use TMPDIR if it is set. If not, set it to /tmp
  if [ -z "$TMPDIR" ]; then
    TMPDIR=/tmp
  fi

  # Strip the trailing / from TMPDIR if there is one
  export TMPDIR="$(echo "$TMPDIR" | sed 's#/$##')"

  # Get the absolute path to command used to start this script. JUNONIA_TARGET
  # can be set to a path to avoid the bootstrap process if that path is known
  # in advance, or can be set in advance. Otherwise bootstrapping will be
  # attempted if the function is defined.
  if [ -z "$JUNONIA_TARGET" ]; then
    if ! JUNONIA_TARGET="$(junonia_bootstrap >/dev/null 2>&1)"; then
      echoerr "failed to bootstrap and init"
      return 1
    fi
  fi

  readonly JUNONIA_TARGET
  export   JUNONIA_TARGET

  if [ -z "$JUNONIA_PATH" ]; then
    # Get the script path, go there, resolve the full path of symlinks with pwd
    # /some/path/to/the/actual
    # /home/user/code/project/name/bin
    JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
  fi

  readonly JUNONIA_PATH
  export   JUNONIA_PATH

  # Get the script name by removing the path and any .sh suffix:
  # script
  readonly JUNONIA_NAME="$(basename "$JUNONIA_TARGET" .sh)"
  export   JUNONIA_NAME
  readonly JUNONIA_CAPNAME="$(awk -v n="$JUNONIA_NAME" \
                              'BEGIN{print toupper(n)}')"
  export   JUNONIA_CAPNAME

  # Path to the config file
  readonly _JUNONIA_CONFIG_DEFAULT="$HOME/.$JUNONIA_NAME/${JUNONIA_NAME}rc.sh"
  readonly JUNONIA_CONFIG="${JUNONIA_CONFIG:-"$_JUNONIA_CONFIG_DEFAULT"}"
  export   JUNONIA_CONFIG

  # Configure if debug messages will be printed.
  junonia_setdebug "$JUNONIA_DEBUG"

  # Indicate that init has happened
  readonly JUNONIA_INIT=1
}


###
### Argument parsing
###

# Use _junonia_get_envvars to examine the current environment using env and
# extract the names of variables of interest. These are the ones that start
# with SCRIPT_.  Unfortunately it is IMPOSSIBLE to determine from the output of
# env what actually are variables just by inspection. It's possible to have a
# multiline variable whose contents looks like a variable assignment:
#
# foo="one=two
# three=four"
#
# So the output of env is:
#
# foo=one=two
# three=four
#
# So 'three' looks like a variable but is not one. Therefore eval is used to
# see if each of the potential names are set [ ${var+set} = set ], meaning they
# are a variable of interest with a value, even if that value is empty, before
# adding the name to the list.
#
# Eval is used very carefully by only sending it things from known sources.
# The output of each line of env that is extracted must match the pattern
# 'SCRIPT_<valid identifier chars>=', and the first field split on = is
# evaluated. Therefore, what is being 'eval'ed is a potential variable name.
_junonia_get_envvars () {
  for v in $(env | awk -F= -v n="$JUNONIA_CAPNAME" \
             '$0 ~ "^" n "_[_A-Za-z0-9]+=" {print $1}'); do
    eval if [ \"'${'$v+set}\" = set ]\; then echo $v\; fi
  done
}

# Accept an argument spec and arguments, produce a list of values for each
# positional argument and option in the spec. If no option was specified, an
# empty value is generated, such that every specified option has a value, even
# if that value is empty.
#
# $1      The full text of a program argument spec.
# $2 - $N The program name and arguments from the command line.
_junonia_set_args () {

  # The configuration file is in a shell format that can be sourced. In order
  # to resolve arguments in the expected order (defaults, config file,
  # environment variables, command line arguments), the config file cannot be
  # directly sourced into this environment, otherwise it will overwrite
  # already-set environment variables. This is worked around in the following
  # manner.
  if [ -f "$JUNONIA_CONFIG" ]; then
    set_vars="$(_junonia_get_envvars)"

    # Once the list of known variables that are already set is made, execute a
    # subshell in a command substitution that outputs the text of some commands
    # to be eval'd. This works by sourcing the configuration file so that all
    # variables are exported (-a), again seeing what variables are now set, and
    # then checking to see if they are in the list of previously set variables.
    # If they are now set, and weren't already set, return some text that will
    # be eval'd to set the variable values.
    #
    # Eval is again used very carefully. Only identifiers are in the list that
    # is iterated over. When the value is obtained, the resolution of the
    # variable v is the variable name, the eval of that gives the *string*
    # value of the variable, and then the resulting export command string
    # encloses that value in single quotes. In this way, the value provided in
    # the configuration file is treated *only as a string*.
    #
    # The resulting list of export commands to be eval'd looks like:
    # export SCRIPT_foo='string value of foo from config file'
    # export SCRIPT_bar='string value of bar from config file'

    evalcmds="$(
      set -a
      . "$JUNONIA_CONFIG"
      for v in $(_junonia_get_envvars); do
        if ! echo "$set_vars" | grep $v; then
          eval echo export $v=\\\'\"'$'$v\"\\\'
        fi
      done
    )"

    eval "$evalcmds"
  fi

  spec="$1"
  shift

  # Spaces and newlines need to be ignored when passing the determined values
  # back. The output will be separated by an RS that will allow this, which
  # will be something like the Record Separator (control character 30).
  awk_prog='
    # All bools are either 1 or empty, but we accept the text true, 1, and the
    # presence of the flag (empty value) as true, and the text false and 0 as
    # false.
    function mapbool(b, opt) {
    if(tolower(b) == "true" || b == "1" || b == "") {
      return "1"
    } else {
      if(tolower(b) == "false" || b == "0") {
        return ""
      } else {
        msg = "option " opt " argument must be omitted (true) or one of:"
        msg = msg "\ntrue false 1 0"
        echoerr(msg)
        e = 1
        exit 1
      }
    }
  }

  BEGIN {
    # Arg 1 is stdin, so skip that and Iterate through the remaining program
    # arguments, which will be either positional (including subcommands),
    # options, or multi-options.
    for (i = 2; i < ARGC; i++) {
      if(substr(ARGV[i], 0, 1) == "-") {
        # This is an option

        # How many times this option has been seen
        opt_num[ARGV[i]]++

        if(substr(ARGV[i+1], 0, 1) == "-") {

          # If the next thing is an option instead of a value, then set the
          # value to empty and move on.
          opts[ARGV[i]] = ""
          delete ARGV[i]

        } else {

          if(opts[ARGV[i]]) {

            # Have already seen this arg once, so it gets another, numbered
            # entry in the opts array.
            opts[ARGV[i] opt_num[ARGV[i]]] = ARGV[i+1]

          } else {

            # Store this arg and its value, which is the next value
            opts[ARGV[i]] = ARGV[i+1]

          }

          # This was an option with a value, so remove both the option and the
          # value (the next argument), and then additionally jump i forward to
          # the next array index, since that does not shift during this loop.
          delete ARGV[i]
          delete ARGV[i+1]
          i++
        }
      } else {
        # This is a positional argument

        # Store and remove the argument
        pos[i-1] = ARGV[i]
        delete ARGV[i]

        # Check for help subcommand
        if(pos[i-1] == "help"   || pos[i-1] == "-h" || pos[i-1] == "-help" ||
           pos[i-1] == "--help" || pos[i-1] == "/h" || pos[i-1] == "/help") {

          # Build the function name to get help on
          func_name = pos[1]

          # e.g. cmd subcommand help
          for(j=2; j<i-1; j++) {
            func_name = func_name "_" pos[j]
          }

          # Check the next arg to see if that should be the func for help
          # e.g. cmd subcommand help subcommand2
          if(ARGV[i+1] && ARGV[i+1] !~ /^-/) {
            func_name = func_name "_" ARGV[i+1]
          }

          print func_name "_help" JRS args
          e = 0
          exit
        }
      }
    }

    # Track the indent level as the spec is processed and values assigned. The
    # indent level is essentially the tree traversal. We go down one path, from
    # the root through all of the subcommand nodes. Along the way each
    # subcommand can have options, and the final subcommand can have positional
    # parameters as well as options. The order of the options and positonal
    # parameters in the spec determines the order of the values that are
    # output.
    indents = ""

    # The collected, IFS separated, ordered argument values that will be
    # returned.
    args = ""

    # The function name to execute, constructed from program_subcommand based
    # on the given arguments.
    func_name = ""

    # Both subcommands and positional arguments are stored in the same
    # positional array. As each is resolved p is incremented to advance through
    # the positional array. Once all subcommands are resolved, helping to build
    # the function name, the remaining positional values are assigned in order
    # as positional values.
    p = 1
  }

  # Skip lines starting with # and blank lines
  /^ #/ || /^$/ {
    next
  }

  {
    # Are we looking at the indent level of the spec that we are interested in?
    indented = $0 ~ "^" indents "[-_A-Za-z0-9]"
  }

  # Spec entry starts with a "-", which indicates an option.
  indented && substr($1, 0, 1) == "-" {
    split($1, a, "=")
    opt = a[1]
    def = a[2]

    if(opt in opts) {
      # This option from the spec is one we have in the program arguments.

      if($2 ~ /\[[A-Za-z0-9]/) {
        # The option can be specified multiple times (brackets around metavar
        # in the spec), so this option may have received multiple values.

        args = args opts[opt]
        delete opts[opt]
        for(i=2; i<=opt_num[opt]; i++) {
          args = args JUS opts[opt i]
          delete opts[opt i]
        }

      } else {
        if($2) {

          # Single value option (no brackets around metavar in spec)
          args = args opts[opt]

        } else {

          # Flag (no metavar in spec)
          if(opts[opt] == "") {
            opts[opt] = def
          }

          args = args mapbool(opts[opt], opt)
        }
        delete opts[opt]
      }
    } else {
      envopt = envname "_" substr(opt, 2)
      gsub(/-/, "_", envopt)

      if(def) {
        args = args mapbool(def, opt)
      } else {
        if($2 !~ /\[[A-Za-z0-9]/) {
          n = index($0, "=")
          if(n) {
            args = args substr($0, n + 1)
          }
        }
      }

      if(ENVIRON[envopt]) {
        if($2) {
          args = args ENVIRON[envopt]
        } else {
          args = args mapbool(ENVIRON[envopt], opt)
        }
      }
    }
    args = args JRS
    next
  }

  # Spec entry does not start with hyphen and is all uppercase, which indicates
  # this is a positional parameter. Assign the current positional parameter
  # value and increment to the next positional value.
  indented && $0 ~ /^ *[_A-Z0-9]+=*/ {
    if(pos[p] != "") {
      args = args pos[p] JRS
      p++
    } else {
      n = index($0, "=")
      if(n) {
        args = args substr($0, n + 1) JRS
      } else {
        args = args "" JRS
      }
    }
    next
  }

  # Spec entry does not start with hyphen and is not all caps, which indicates
  # this is a subcommand. Start or add to the function name which will be
  # executed and increment to the next positional value.
  indented && $1 == pos[p] {
    if(func_name) {
      envname = envname "_" $1
      func_name = func_name "_" $1
    } else {
      envname = toupper($1)
      func_name = $1
    }
    indents = indents "  "
    p++
    next
  }

  END {
    # There was an error and we should just exit.
    if(e) {
      exit e
    }

    # There are leftover parameters so something was invalid.
    if(pos[p]) {
      echoerr("unknown parameter: " pos[p])
      exit 1
    }

    # There are leftover options so something was invalid.
    for(i in opts) {
      echoerr("unknown option: " i)
      exit 1
    }

    # Output everything properly separated for processing.
    print func_name JRS args
  }'

  echo "$spec" | awk -v JRS="$JUNONIA_RS" -v JUS="$JUNONIA_US" \
                     "$JUNONIA_AWKS $awk_prog" - "$@"
}


###
### User facing run entry functions
###

# Perform a search for defaults and run with them if found.
junonia_run () {
  junonia_init

  # Look for a filter function named
  # ${JUNONIA_NAME}_junonia_filter (e.g. myscript_junonia_filter)
  if command -v ${JUNONIA_NAME}_junonia_filter >/dev/null 2>&1; then
    filter_func=${JUNONIA_NAME}_junonia_filter
  else
    fulter_func=
  fi

  # Look in some particular paths for program markdown documentation.
  for docdir in "$JUNONIA_PATH/../usr/share/doc/$JUNONIA_NAME" \
                "$JUNONIA_PATH/docs" \
                "$JUNONIA_PATH/doc"; do
    if [ -d "$docdir" ] && [ -f "$docdir/$JUNONIA_NAME.md" ]; then
      JUNONIA_DOCDIR="$docdir"
    fi
  done

  # A directory containing markdown docs was found. Run with it.
  if [ -n "$JUNONIA_DOCDIR" ]; then
    junonia_runmd_filtered "$filter_func" "$JUNONIA_DOCDIR" "$@"
    return $?
  fi

  # There is a markdown file in the same dir as the script named `script.md`.
  # Run with it.
  if [ -f "$JUNONIA_PATH/$JUNONIA_NAME.md" ]; then
    junonia_runmd_filtered "$filter_func" "$JUNONIA_PATH/$JUNONIA_NAME.md" "$@"
    return $?
  fi

  # There is a shell function that can provide a spec named
  # script_junonia_spec
  # so run with it.
  if command -v ${JUNONIA_NAME}_junonia_spec >/dev/null 2>&1; then
    spec="$(${JUNONIA_NAME}_junonia_spec)"
    if [ -n "$spec" ]; then
      junonia_runspec_filtered "$filter_func" "$spec" "$@"
      return $?
    else
      echoerr "program argument spec was empty"
      return 1
    fi
  fi

  echoerr "unable to locate docs or spec needed to run"
  return 1
}

# Take a docs dir of md files, one md file, or md contents as a string, make
# the spec, run the function with the parsed arg values.
junonia_runmd () {
  junonia_runmd_filtered "" "$@"
}

# Take a docs dir of md files, one md file, or md contents as a string, make
# the spec, put the results through the filter function, then run the function
# with the parsed arg values (which may have been changed by the filter
# function).
junonia_runmd_filtered () {
  filter_func="$1"
  shift

  md="$1"
  shift

  spec=
  ret=1
  spec_src_type=
  if [ -d "$md" ]; then
    readonly JUNONIA_DOCDIR="$md"
    spec="$(_junonia_md2spec "$md"/*.md)"
    ret=$?
    spec_src_type="dir"
  elif [ -f "$md" ]; then
    spec="$(_junonia_md2spec "$md")"
    ret=$?
    spec_src_type="file"
  elif [ "$(echo "$md" | wc -l)" -gt 1 ]; then
    spec="$(echo "$md" | _junonia_md2spec -)"
    ret=$?
    spec_src_type="md_string"
  fi

  if [ -z "$spec" ] || [ "$ret" -ne 0 ]; then
    echoerr "Unable to generate spec from source provided: $md"
    echoerr "Source should be a directory of Markdown, a Markdown file,"
    echoerr "or a shell string variable containing the Markdown contents."
    return 1
  fi

  _junonia_run_final "$filter_func" "$md" "$spec_src_type" "$spec" "$@"
}

# Take a spec string, run the function with the parsed args values.
junonia_runspec () {
  junonia_runspec_filtered "" "$@"
}

# Take a spec string, put the results through the filter function, then run the
# function with the parsed arg values (which may have been changed by the
# filter function).
junonia_runspec_filtered () {
  filter_func="$1"
  shift

  _junonia_run_final "$filter_func" "" "spec_string" "$@"
}


###
### Run execution
###

_junonia_run_final () {
  filter_func="$1"
  shift

  md="$1"
  shift

  spec_src_type="$1"
  shift

  spec="$1"
  shift

  # Ready to start the run, so set up the execution environment. If junonia_run
  # was called with auto-discovery then this already happened, but it's always
  # safe to rerun init as it has a guard.
  junonia_init

  # The argument values in the order defined in the spec.
  if ! arg_vals="$(_junonia_set_args "$spec" "$JUNONIA_NAME" "$@")"; then
    # An error should have been supplied on stderr
    return 1
  fi

  # Since we're handling values that can be explicitly blank / empty, and
  # values that have whitespace that might need to be preserved, it's easiest
  # to change the IFS to something other than space/tab/newline.
  IFS="$JUNONIA_RS"

  # Pass the execution info to a filter function. This allows us to handle the
  # argument values as $@, and use shift to remove common options as specified
  # by the filter function. Using a user filter function is optional, and in
  # that case every function will receive every option; all common options in
  # the spec tree path.
  _junonia_exec "$filter_func" "$md" "$spec_src_type" "$spec" $arg_vals
}

# Receive function argument values, send them through the filter if needed,
# then execute the specified function with the values.
_junonia_exec () {
  # Each value from the parsed args are now their own word, so the IFS can go
  # back to normal.
  unset IFS

  filter_func="$1"
  shift

  md="$1"
  shift

  spec_src_type="$1"
  shift

  spec="$1"
  shift

  func="$1"
  shift

  if [ -z "$func" ]; then
    echoerr "no operation given to perform"
    return 1
  fi

  # Check for help
  helpfunc=
  if echo "$func" | grep -Eq '_help$'; then
    helpfunc="${func%_help}"
  fi

  if [ -n "$helpfunc" ]; then
    cmd="$(echo $helpfunc | sed 's/_/ /g')"
    case "$spec_src_type" in
      dir)
        if [ -f "$md/$helpfunc.md" ]; then
          {
            cat "$md/$helpfunc.md"
            find -E "$md" -type f -regex "$md/$helpfunc"'_[^_]+\.md' \
               -exec cat {} \;
          } | _junonia_md2help "$cmd"
        else
          if command -v $helpfunc >/dev/null 2>&1; then
            echoerr "help not found for command: $cmd"
          else
            echoerr "command not found: $cmd"
          fi
        fi
        return 0
        ;;
      file)
        cat "$md" | _junonia_md2help "$cmd"
        return 0
        ;;
      md_string)
        echo "$md" | _junonia_md2help "$cmd"
        return 0
        ;;
      spec_string)
        echo "$spec" | awk '{sub(/^# /, ""); print}'
        return 0
        ;;
    esac
  fi

  shift_n=0

  # If there is a filter function, then run it.
  if [ -n "$filter_func" ] && command -v "$filter_func" >/dev/null 2>&1; then
     $filter_func "$@"
     shift_n=$?
  fi

  # The filter function might indicate via its return value that we should
  # shift off some common (and possibly other) values.
  i=0
  while [ $i -lt $shift_n ]; do
    shift
    i=$(( $i + 1 ))
  done

  # If the command hasn't already been sourced or defined somewhere, try to
  # discover it by checking for files corresponding to the function name.
  i=0
  while ! command -v $func >/dev/null 2>&1; do
    case $i in
      0) p="$JUNONIA_PATH/$func.sh";;
      1) p="$JUNONIA_PATH/cmd/$func.sh";;
      2) p="$JUNONIA_PATH/cmds/$func.sh";;
      3) p="$JUNONIA_PREFIX/lib/$JUNONIA_NAME/$func.sh";;
      4) p="$JUNONIA_PREFIX/lib/$JUNONIA_NAME/cmd/$func.sh";;
      5) p="$JUNONIA_PREFIX/lib/$JUNONIA_NAME/cmds/$func.sh";;
      6) p="$JUNONIA_PREFIX/lib/$JUNONIA_NAME/command/$func.sh";;
      7) p="$JUNONIA_PREFIX/lib/$JUNONIA_NAME/commands/$func.sh";;
      *)
        echoerr "command not found: $(echo $func | sed 's/_/ /g')"
        return 1
        ;;
    esac

    i=$(( $i + 1 ))

    # Found the function file, source it.
    if [ -f "$p" ]; then
      . "$p"

      # Only stop the search if the sourced file actually contained the
      # function.
      if command -v $func >/dev/null 2>&1; then
        break
      fi
    fi
  done

  # A function file was found and sourced, and the function was found. Execute
  # the function.
  $func "$@"
}
