###
### Global constants
###

_JUNONIA_IFS=""
_JUNONIA_WRAP=78
_JUNONIA_COL1=18
_JUNONIA_COL2=60

###
### AWK functions
###

# Wrap a long line to a specified width and optionally prefixed
awk_hardwrap='
  function hardwrap(line, width, pre,
                    str, n, wrapped) {
    while(length(line) > width) {
      n = index(line, " ")
      if(n == 0) {
        break
      }

      if(n > width) {
        str = substr(line, 1, n - 1)
      } else {
        str = substr(line, 1, width)
      }

      sub(/ [^ ]*$/, "", str)
      sub(/^ /, "", str)
      wrapped = wrapped pre str "\n"
      line = substr(line, length(str) + 2, length(line))
    }

    if(line) {
      sub(/^ */, "", line)
      wrapped = wrapped pre line "\n"
    }

    return substr(wrapped, 1, length(wrapped) - 1)
  }
'

awk_twocol='
  function twocol(text1, text2, col1, col2, gutter, pre,
                  fmt, text1a, text2a, i, formatted) {
    text1 = hardwrap(text1, col1)
    text2 = hardwrap(text2, col2)
    gutter = sprintf("%" gutter "s", "")
    fmt = pre "%-" col1 "s" gutter "%-" col2 "s"

    split(text1, text1a, "\n")
    split(text2, text2a, "\n")

    i = 1
    while(text1a[i] || text2a[i]) {
      formatted = formatted sprintf(fmt, text1a[i], text2a[i]) "\n"
      i++
    }

    return substr(formatted, 1, length(formatted) - 1)
  }
'

JUNONIA_AWKS="$awk_hardwrap $awk_twocol"

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
    # * `-option VAL1 [-option1 VAL2 ...]`
    options && /^\* `-[-A-Za-z0-9]+/ {
      gsub(/^\* `|`$/, "")

      if(NF > 2) {
        # Defaults are not allowed for multi-opts
        opts[++n_opts] = $2 " [" $3 "]"
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
      txt = txt twocol(subcmd, $0, col1 - 3, col2, 1, "  ") "\n"
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
      txt = txt twocol(param_col1, $0, col1 - 3, col2, 1, "  ") "\n"
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
        txt = txt twocol(opt_col1, $0, col1 - 3, col2, 1, "  ") "\n\n"
      }
    }

    END {
      sub(/\n*$/, "", txt)
      print txt
    }
  '

  if [ -z "$1" ]; then
    echo "Command text required to generate help"
    return 1
  fi

  cat | awk -v wrap="$_JUNONIA_WRAP" -v col1="$_JUNONIA_COL1" \
            -v col2="$_JUNONIA_COL2" -v cmd="$1" \
            "$JUNONIA_AWKS $awk_prog"
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
  # spaces and newlines need to be ignored when passing the determined values
  # back.  The output will be separated by this IFS, which will be something
  # like the Record Separator (control character 30).
  echo "$spec" | awk -v recsep="$_JUNONIA_IFS" '
  function mapbool(b, opt) {
    if(tolower(b) == "true" || b == "1") {
      return "1"
    } else {
      if(tolower(b) == "false" || b == "0") {
        return ""
      } else {
        msg = "option " opt " argument must be omitted (true) or one of:"
        msg = msg "\ntrue false 1 0"
        print msg > "/dev/stderr"
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

        # Check for help subcommand
        if(pos[i-1] == "help") {

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

          print func_name "_help" recsep args
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

      if($2 ~ /\[[A-Za-z0-9]+/) {
        # The option can be specified multiple times (brackets around metavar
        # in the spec), so this option may have received multiple values.

        args = args opts[opt]
        delete opts[opt]
        for(i=2; i<=opt_num[opt]; i++) {
          args = args "\n" opts[opt i]
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

          args = args mapbool(opts[opt])
        }
        delete opts[opt]
      }
    } else {
      if(def) {
        args = args mapbool(def)
      } else {
        n = index($0, "=")
        if(n) {
          args = args substr($0, n + 1)
        }
      }
    }
    args = args recsep
    next
  }

  # Spec entry does not start with hyphen and is all uppercase, which indicates
  # this is a positional parameter. Assign the current positional parameter
  # value and increment to the next positional value.
  indented && $0 ~ /^ *[_A-Z0-9]+=*/ {
    if(pos[p] != "") {
      args = args pos[p] recsep
      p++
    } else {
      n = index($0, "=")
      if(n) {
        args = args substr($0, n + 1) recsep
      } else {
        args = args "" recsep
      }
    }
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
    if(e) {
      exit e
    }

    if(pos[p]) {
      print "unknown parameter: " pos[p] > "/dev/stderr"
      exit 1
    }

    for(i in opts) {
      print "unknown option: " i > "/dev/stderr"
      exit 1
    }

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

  md="$1"
  shift

  spec_src_type="$1"
  shift

  spec="$1"
  shift

  func="$1"
  shift

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
            echo "help not found for command: $cmd"
          else
            echo "command not found: $cmd"
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

  if [ -n "$func" ] && command -v $func >/dev/null 2>&1; then
    $func "$@"
  else
    echo "command not found: $(echo "$func" | sed 's/_/ /g')" 1>&2
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

  md="$1"
  shift

  spec=
  ret=1
  spec_src_type=
  if [ -d "$md" ]; then
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
    echo "Unable to generate spec from source provided: $md" 1>&2
    echo "Source should be a directory of Markdown, a Markdown file, or" 1>&2
    echo "a shell string variable containing the Markdown contents." 1>&2
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

_junonia_run_final () {
  filter_func="$1"
  shift

  md="$1"
  shift

  spec_src_type="$1"
  shift

  spec="$1"
  shift

  # The argument values in the order defined in the spec.
  if ! arg_vals="$(_junonia_parse_args "$spec" "$(basename "$0")" "$@")"; then
    # An error should have been supplied on stderr
    return 1
  fi

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
  _junonia_proxy_func "$filter_func" "$md" "$spec_src_type" "$spec" $arg_vals
}
