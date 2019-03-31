###
### Global constants
###

_JUNONIA_IFS=""

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
      description = 0
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

    /^### Description/ {
      description = 1
    }

    /^### Positional parameters/ {
      positional = 1
    }

    #* `POS_ONE`
    positional && /^\* `[-_A-Z0-9]+`/ {
      gsub(/`/, "")
      params[++n_params] = $2
    }

    /^### Options/ {
      options = 1
    }

    #* `-option`
    #* `-option VAL`
    #* `-option VAL1 [-option1 VAL2 ...]`
    options && /^\* `-[-A-Za-z0-9]+/ {
      gsub(/`/, "")

      if(NF > 3) {
        opts[++n_opts] = $2 " [" $3 "]"
      } else {
        opts[++n_opts] = $2 " " $3
      }
    }

    END {
      spec()
    }
  ' "$@"
}

###
### Argument parsing and program execution
###

# Accept an argument spec and arguments, produce a list of values for each
# positional argument and option in the spec. If no option was specified, an
# empty value is generated, such that every specified option has a value, even
# if that value is empty.
_junonia_parse_args () {

  # $1      The full text of a program argument spec.
  # $2 - $N The program name and arguments from the command line.
  spec="$1"
  shift

  # We expect IFS to have been set to some non-default value, since things like
  # spaces and newlines need to be ignored when passing the determined values back.
  # The output will be separated by this IFS, which will be something like the Record 
  # Separator (control character 30).
  echo "$spec" | awk -v recsep="$_JUNONIA_IFS" '
  BEGIN {
    # Arg 1 is stdin, so skip that and Iterate through the remaining program
    # arguments, which will be either positional (including subcommands),
    # options, or multi-options.
    for (i = 2; i < ARGC; i++) {
      if(substr(ARGV[i], 0, 1) == "-") {
        # Option

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

        # Store the positional argument
        pos[i-1] = ARGV[i]
        delete ARGV[i]

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

  {
    # Are we looking at the indent level of the spec that we are interested in?
    indented = $0 ~ "^" indents "[-_A-Za-z0-9]"
  }

  # Spec entry starts with a "-", which indicates an option.
  indented && substr($1, 0, 1) == "-" {
    if($1 in opts) {
      # This option from the spec is one we have in the program arguments.

      if($2 ~ /\[[A-Za-z0-9]+/) {
        # The option can be specified multiple times (brackets around metavar
        # in the spec), so this option may have received multiple values.

        args = args opts[$1]
        for(i=2; i<=opt_num[$1]; i++) {
          args = args "\n" opts[$1 i]
        }

      } else {
        if(opts[$1]) {
          # Single value option (no brackets around metavar in spec)
          args = args opts[$1]
        } else {
          # Flag (no metavar in spec)
          args = args "1"
        }
      }
    }
    args = args recsep
    next
  }

  # Spec entry does not start with hyphen and is all uppercase, which indicates
  # this is a positional parameter. Assign the current positional parameter
  # value and increment to the next positional value.
  indented && $1 == toupper($1) {
    args = args pos[p] recsep
    p++
    next
  }

  # Spec entry does not start with hyphen and is not all caps, which indicates
  # this is a subcommand. Start or add to the function name which will be
  # executed and increment to the next positional value.
  indented && $1 == pos[p] {
      if(func_name) {
        func_name = func_name "_" $1
      } else {
        func_name = $1
      }
      indents = indents "  "
      p++
      next
  }

  END {
    print func_name recsep args
  }' - "$@"
}

# Receive function argument values, send them through the filter if needed,
# then execute the specified function with the values.
_junonia_proxy_func () {
  # Each value from the parsed args are now their own word, so the IFS can go
  # back to normal.
  unset IFS

  filter_func="$1"
  shift

  func="$1"
  shift

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

  if [ -n "$func" ] && command -v $func >/dev/null 2>&1; then
    $func "$@"
  else
    echo "command not found: $func" 1>&2
    return 1
  fi
}

# Take a docs dir of md files, make spec, run the function with the parsed arg
# values.
junonia_runmd () {
  junonia_runmd_filtered "" "$@"
}

# Take a docs dir of md files, make spec, put the results through the filter
# function, then run the function with the parsed arg values (which may have
# been changed by the filter function).
junonia_runmd_filtered () {
  filter_func="$1"
  shift

  docs="$1"
  shift

  if [ ! -d "$docs" ]; then
    echo "Docs dir could not be found: $docs"
    return 1
  fi

  spec="$(_junonia_md2spec "$docs"/*.md)"

  junonia_runspec_filtered "$filter_func" "$spec" "$@"
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

  spec="$1"
  shift

  # The argument values in the order defined in the spec.
  arg_vals="$(_junonia_parse_args "$spec" "$(basename "$0")" "$@")"

  # Since we're handling values that can be explicitly blank / empty, and
  # values that have whitespace that might need to be preserved, it's easiest
  # to change the IFS to something other than space/tab/newline. We use the
  # Record Separator (RS) control character (decimal 30).
  IFS="$_JUNONIA_IFS"

  # Pass the execution info to a proxy function. This allows us to handle the
  # argument values as $@, and use shift to remove common options as specified
  # by the filter function. Using a filter function is optional, and in that
  # case every function will receive every option; all common options in the
  # tree path.
  _junonia_proxy_func "$filter_func" $arg_vals
}

