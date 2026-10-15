#!/bin/sh
#
# Smoke tests for junonia.
#
# Part one runs the bundled examples, which cover the five ways a program can
# supply its documentation and argument spec.
#
# Part two generates a program in a scratch directory and walks the argument
# resolution matrix: spec defaults, configuration file, environment variables,
# command line values, booleans, repeatable options, positional parameters, and
# the error paths. Most cases assert against the exact text the command function
# receives, because turning a spec plus an environment into a precise, ordered
# argument list is most of what junonia does.
#
# Part three repeats the interesting cases for a program configured by a spec
# string instead of Markdown, which takes a different path through junonia.
#
# Usage: test/smoke.sh [-v]
#   -v  also print the output of each failing check
#
# Nothing outside the scratch directory is touched. The HOME, configuration
# file, and cache directory used by the generated programs all live there.

set -u

me="$(basename "$0")"
verbose=0
[ "${1:-}" = "-v" ] && verbose=1

testdir="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$testdir")"
export JUNONIA_ROOT="$root"

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/junonia-smoke.XXXXXX")" || exit 1
cleanup() {
  if [ -n "${JUNONIA_SMOKE_KEEP:-}" ]; then
    printf 'sandbox kept: %s\n' "$sandbox" >&2
    return
  fi
  chmod -R u+w "$sandbox" 2>/dev/null
  rm -rf "$sandbox"
}
trap cleanup EXIT
trap 'echo "$me: interrupted" >&2; exit 1' INT TERM

# Keep the programs under test away from the real user configuration.
export HOME="$sandbox/home"
export JUNONIA_CONFIGDIR="$sandbox/config"
export JUNONIA_CONFIG="$sandbox/config/progrc"
export JUNONIA_CACHEDIR="$sandbox/cache"
export JUNONIA_CACHE=0
mkdir -p "$HOME" "$JUNONIA_CONFIGDIR" "$JUNONIA_CACHEDIR"

n_tests=0
n_fail=0
failures=

###
### Assertion helpers
###

# check NAME EXPECTED ACTUAL
check() {
  n_tests=$((n_tests + 1))
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
    return 0
  fi
  n_fail=$((n_fail + 1))
  failures="$failures
  $1"
  printf 'FAIL %s\n' "$1"
  if [ "$verbose" = 1 ]; then
    printf '     expected:\n%s\n' "$(printf '%s\n' "$2" | sed 's/^/       /')"
    printf '     actual:\n%s\n'   "$(printf '%s\n' "$3" | sed 's/^/       /')"
  fi
  return 1
}

# check_contains NAME HAYSTACK NEEDLE
check_contains() {
  n_tests=$((n_tests + 1))
  case "$2" in
    *"$3"*) printf 'ok   %s\n' "$1"; return 0 ;;
  esac
  n_fail=$((n_fail + 1))
  failures="$failures
  $1"
  printf 'FAIL %s (expected to find "%s")\n' "$1" "$3"
  if [ "$verbose" = 1 ]; then
    printf '     actual:\n%s\n' "$(printf '%s\n' "$2" | sed 's/^/       /')"
  fi
  return 1
}

# replace ACTUAL OLD NEW - rewrite one line of an expected block so that each
# check only states what differs from the baseline.
replace() {
  printf '%s\n' "$1" | awk -v old="$2" -v new="$3" '
    !done && $0 == old { print new; done = 1; next }
    { print }'
}

###
### Part one: the bundled examples
###

printf '### bundled examples\n'

# run_in DIR [ARGS...] - sets out and rc
run_in() {
  dir="$1"
  shift
  out="$( cd "$dir" && "$@" 2>&1 )"
  rc=$?
}

run_in "$root/examples/run_from_defaults" ./prog
check 'run_from_defaults: top level' '0' "$rc"
check_contains 'run_from_defaults: top level output' "$out" \
  'Run `prog help` options and subcommands'

run_in "$root/examples/run_from_defaults" ./prog sub1
check 'run_from_defaults: subcommand defaults' \
  '-shared-arg: shared_default
-sub1-opt1:  
-bool1:      
-bool2:      1' "$out"

run_in "$root/examples/run_from_defaults" ./prog sub1 -sub1-opt1 X
check 'run_from_defaults: option value' \
  '-shared-arg: shared_default
-sub1-opt1:  X
-bool1:      
-bool2:      1' "$out"

run_in "$root/examples/run_from_defaults" ./prog sub1 -bool1
check 'run_from_defaults: flag' \
  '-shared-arg: shared_default
-sub1-opt1:  
-bool1:      1
-bool2:      1' "$out"

run_in "$root/examples/run_from_defaults" ./prog sub1 sub11
check 'run_from_defaults: nested subcommand' \
  '-shared-arg: shared_default
-sub1-opt1:  
-bool1:      
-bool2:      1
-sub11-opt1: ' "$out"

run_in "$root/examples/run_from_defaults" ./prog sub2 hello
check 'run_from_defaults: positional parameter' \
  '-shared-arg: shared_default
POS1:        hello
-sub2-opt1:  
-sub2-opt2:  ' "$out"

run_in "$root/examples/run_from_defaults" ./prog help
check_contains 'run_from_defaults: help lists subcommands' "$out" 'sub1'
check_contains 'run_from_defaults: help lists options' "$out" '-shared-arg'

run_in "$root/examples/run_from_md" ./prog sub1 -sub1-opt1 X
check 'run_from_md: option value' \
  '-shared-arg: shared_default
-sub1-opt1:  X' "$out"

run_in "$root/examples/run_from_mdfile" ./prog sub1 -sub1-opt1 X
check 'run_from_mdfile: option value' \
  '-shared-arg: 
-sub1-opt1:  X' "$out"

run_in "$root/examples/run_from_mdstring" ./prog sub1 -sub1-opt1 X
check 'run_from_mdstring: option value' \
  '-shared-arg: 
-sub1-opt1:  X' "$out"

run_in "$root/examples/run_from_spec" ./prog sub1
check 'run_from_spec: defaults' \
  '-shared-arg: shared_default
-param1    : p
-sub1-opt1 : 
-bool1     : 
-bool2     : ' "$out"

run_in "$root/examples/run_from_spec" ./prog sub2 hello
check 'run_from_spec: positional parameter' \
  '-shared-arg: shared_default
-POS1:       hello
-sub2-opt1:  
-sub2-opt2:  ' "$out"

###
### Part two: argument resolution, Markdown driven
###

printf '\n### argument resolution (markdown)\n'

app="$sandbox/prog"
mkdir -p "$app/cmd" "$app/doc"

# The command function reports what it was given, one argument per line. Note
# that positional parameters always precede options, and that options of parent
# commands are passed along too, both in the order declared in the docs.
cat > "$app/prog" <<'PROGEOF'
#!/bin/sh
prog () {
  echo "prog: shared=[$1]"
}

# A copy of junonia_bootstrap
junonia_bootstrap () {
  JUNONIA_TARGET="$0"
  while [ -h "$JUNONIA_TARGET" ]; do
    JUNONIA_PATH=$(readlink "$JUNONIA_TARGET")
    if [ "$(echo "$JUNONIA_PATH" | cut -c -1)" = "/" ]; then
      JUNONIA_TARGET="$JUNONIA_PATH"
    else
      JUNONIA_TARGET="$(dirname "$JUNONIA_TARGET")/$JUNONIA_PATH"
    fi
  done
  JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
  JUNONIA_TARGET="$JUNONIA_PATH/$(basename "$JUNONIA_TARGET")"
  if [ "$(basename "$JUNONIA_PATH")" = bin ]; then
    JUNONIA_PATH="$(dirname "$JUNONIA_PATH")"
  fi
}
junonia_bootstrap
. "$JUNONIA_ROOT/junonia"
junonia_run "$@"
PROGEOF
chmod +x "$app/prog"

cat > "$app/cmd/prog_opts.sh" <<'CMDEOF'
prog_opts () {
  echo "shared=[$1]"
  echo "pos1=[$2]"
  echo "opt=[$3]"
  echo "optdef=[$4]"
  echo "flag=[$5]"
  echo "flag_one=[$6]"
  echo "flag_false=[$7]"
  echo "flag_true=[$8]"
  echo "flag_zero=[$9]"
  echo "multi=[${10}]"
}
CMDEOF

# prog_ghost has no implementation file, prog_missing has one that defines
# nothing. Both must report and exit.
cat > "$app/doc/prog_ghost.md" <<'MDEOF'
## `prog ghost`

Documented, but deliberately not implemented.

### Synopsis

    prog ghost
MDEOF

cat > "$app/doc/prog_missing.md" <<'MDEOF'
## `prog missing`

Documented, with an implementation file that defines nothing.

### Synopsis

    prog missing
MDEOF

cat > "$app/cmd/prog_missing.sh" <<'CMDEOF'
# Intentionally empty; prog_missing must not be defined here.
CMDEOF

# Two levels of subcommands, for nested help and nested execution. Neither has
# a positional parameter: with both, an option value and a subcommand name are
# indistinguishable, positional parameters being resolved first.
cat > "$app/doc/prog_nest.md" <<'MDEOF'
## `prog nest`

Holds a subcommand.

### Synopsis

    prog nest [OPTIONS] SUBCOMMAND

### Description

A subcommand of its own.

### Options

* `-n, -nest-opt N`

An option of the nesting subcommand, with an alias. [default: `nest_default`]
MDEOF

cat > "$app/doc/prog_nest_deep.md" <<'MDEOF'
## `prog nest deep`

Documentation for a subcommand two levels down.

### Synopsis

    prog nest deep [OPTIONS]

### Description

Nothing to see here.

### Options

* `-deep-opt D`

An option of a deeply nested subcommand.
MDEOF

# The documented separator variables, and the documented way to iterate over a
# repeatable option.
cat > "$app/doc/prog_multi.md" <<'MDEOF'
## `prog multi`

Collects a repeatable option.

### Synopsis

    prog multi [OPTIONS]

### Options

* `-many M [-many M2 ...]`

May be given more than once.
MDEOF

cat > "$app/cmd/prog_multi.sh" <<'CMDEOF'
prog_multi () {
  # $1 is the shared option of the program itself; $2 is this option
  IFS=$JUNONIA_US
  for val in $2; do
    unset IFS
    echo "many=[$val]"
    IFS=$JUNONIA_US
  done
  unset IFS
}
CMDEOF

cat > "$app/doc/prog_seps.md" <<'MDEOF'
## `prog seps`

Reports the separator variables junonia provides.

### Synopsis

    prog seps
MDEOF

cat > "$app/cmd/prog_seps.sh" <<'CMDEOF'
prog_seps () {
  for name in JUNONIA_US JUNONIA_FS JUNONIA_RS JUNONIA_GS; do
    eval "value=\$$name"
    printf '%s=%s\n' "$name" \
      "$(printf '%s' "$value" | od -An -tx1 | tr -d ' \n')"
  done
}
CMDEOF

cat > "$app/cmd/prog_nest.sh" <<'CMDEOF'
prog_nest () {
  echo "shared=[$1] nest_opt=[$2]"
}
CMDEOF

cat > "$app/cmd/prog_nest_deep.sh" <<'CMDEOF'
prog_nest_deep () {
  echo "shared=[$1] nest_opt=[$2] deep_opt=[$3]"
}
CMDEOF

# JSON options build a request body rather than the argument list, so their
# documented defaults go somewhere else entirely.
cat > "$app/doc/prog_json.md" <<'MDEOF'
## `prog json`

Report the JSON body junonia builds from JSON options.

### Synopsis

    prog json [JSON_OPTIONS] [OPTIONS]

### Description

Prints the body on one line.

### Options

* `.enabled=true`

A boolean defaulting to true.

* `.disabled=false`

A boolean defaulting to false.

* `.bare`

A boolean with no default.

* `.name NAME`

A JSON string with no default.

* `.nick NICK`

A JSON string with a default. [default: `nicko`]

* `-plain P`

An ordinary option, to show that JSON options take no argument slot. [default: `pp`]
MDEOF

cat > "$app/cmd/prog_json.sh" <<'CMDEOF'
prog_json () {
  echo "json=[$JW_JSON]"
  echo "argc=$#"
  echo "shared=[$1]"
  echo "plain=[$2]"
}
CMDEOF

cat > "$app/doc/prog.md" <<'MDEOF'
## `prog`

Test program for the junonia smoke tests.

### Synopsis

    prog [SUBCOMMAND] [OPTIONS]

### Description

Exercises argument resolution.

### Options

* `-shared SHARED`

An option shared by every subcommand. [default: `shared_default`]
MDEOF

cat > "$app/doc/prog_opts.md" <<'MDEOF'
## `prog opts`

Report the values junonia resolves for each kind of argument.

### Synopsis

    prog opts [POS1] [OPTIONS]

### Description

Prints every resolved value on its own line.

### Positional parameters

* `POS1`

A positional parameter.

### Options

* `-opt OPT`

An option with no default.

* `-optdef OPTDEF`

An option with a default. [default: `optdef_default`]

* `-flag`

A boolean with no default.

* `-flag-one=1`

A boolean defaulting to true.

* `-flag-false=false`

A boolean defaulting to false.

* `-flag-true=true`

A boolean defaulting to true.

* `-flag-zero=0`

A boolean defaulting to false, written as zero.

* `-multi M [-multi M2 ...]`

An option that may be repeated.
MDEOF

# Environment variables are second only to the command line, so each case
# starts from a known empty set of them.
clear_prog_env() {
  for v in $(env | grep '^PROG_' | cut -d= -f1); do
    unset "$v"
  done
}

# run_with DIR [NAME=VALUE ...] [PROGRAM ARGS...]
#
# Runs the program in DIR with a clean set of PROG_ variables plus whatever
# assignments are given for this case. Assignments go through env rather than a
# shell prefix because `VAR=x some_function` leaves VAR set in the calling shell
# when the command is a function.
run_with() {
  dir="$1"
  shift
  assigns=
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; break ;;
      *=*) assigns="$assigns $1"; shift ;;
      *) break ;;
    esac
  done
  clear_prog_env
  # shellcheck disable=SC2086
  run_in "$dir" env $assigns ./prog "$@"
}

run_app() {
  run_with "$app" "$@"
}

: > "$JUNONIA_CONFIG"

# Booleans are normalized: 1 for true, the null value for false, no matter how
# the value was written or where it came from.
BASE='shared=[shared_default]
pos1=[]
opt=[]
optdef=[optdef_default]
flag=[]
flag_one=[1]
flag_false=[]
flag_true=[1]
flag_zero=[]
multi=[]'

run_app opts
check 'all defaults' "$BASE" "$out"

run_app opts -opt given
check 'option value' "$(replace "$BASE" 'opt=[]' 'opt=[given]')" "$out"

run_app opts first
check 'positional value' "$(replace "$BASE" 'pos1=[]' 'pos1=[first]')" "$out"

run_app opts -shared parents
check 'shared option value' \
  "$(replace "$BASE" 'shared=[shared_default]' 'shared=[parents]')" "$out"

run_app opts -flag
check 'flag given' "$(replace "$BASE" 'flag=[]' 'flag=[1]')" "$out"

run_app opts -flag-false
check 'false default, flag given' \
  "$(replace "$BASE" 'flag_false=[]' 'flag_false=[1]')" "$out"

run_app opts -flag-true
check 'true default, flag given' "$BASE" "$out"

run_app opts -flag true
check 'flag explicit true' "$(replace "$BASE" 'flag=[]' 'flag=[1]')" "$out"

run_app opts -flag 1
check 'flag explicit 1' "$(replace "$BASE" 'flag=[]' 'flag=[1]')" "$out"

run_app opts -flag false
check 'flag explicit false' "$BASE" "$out"

run_app opts -flag 0
check 'flag explicit 0' "$BASE" "$out"

run_app opts -flag-true false
check 'true default, set false' "$(replace "$BASE" 'flag_true=[1]' 'flag_true=[]')" "$out"

run_app opts -flag-one false
check 'default 1, set false' "$(replace "$BASE" 'flag_one=[1]' 'flag_one=[]')" "$out"

run_app opts -flag maybe
check 'invalid boolean rejected' '1' "$(( rc != 0 ))"
check_contains 'invalid boolean message' "$out" \
  'argument must be omitted (true) or one of'

# Precedence: spec default < config file < environment < command line.
: > "$JUNONIA_CONFIG"

# Note that only the program name is capitalized in an argument variable; the
# subcommand keeps its own case, so these are PROG_opts_flag, not PROG_OPTS_FLAG.
run_app PROG_opts_opt=from_env opts
check 'environment supplies option' \
  "$(replace "$BASE" 'opt=[]' 'opt=[from_env]')" "$out"

# A value of 0 is a value, not an unset variable.
run_app PROG_opts_opt=0 opts
check 'environment supplies numeric zero' \
  "$(replace "$BASE" 'opt=[]' 'opt=[0]')" "$out"

run_app PROG_shared=from_env opts
check 'environment supplies shared option' \
  "$(replace "$BASE" 'shared=[shared_default]' 'shared=[from_env]')" "$out"

run_app PROG_opts_flag=true opts
check 'environment boolean true' \
  "$(replace "$BASE" 'flag=[]' 'flag=[1]')" "$out"

run_app PROG_opts_flag_one=false opts
check 'environment boolean false' \
  "$(replace "$BASE" 'flag_one=[1]' 'flag_one=[]')" "$out"

printf 'PROG_opts_opt=from_file\nPROG_opts_optdef=file_def\n' > "$JUNONIA_CONFIG"

run_app opts
check 'config file values' "$(replace "$(replace "$BASE" 'opt=[]' 'opt=[from_file]')" \
  'optdef=[optdef_default]' 'optdef=[file_def]')" "$out"

run_app PROG_opts_opt=from_env opts
check 'environment beats config file' \
  "$(replace "$(replace "$BASE" 'opt=[]' 'opt=[from_env]')" \
  'optdef=[optdef_default]' 'optdef=[file_def]')" "$out"

run_app opts -opt from_cli
check 'command line beats config file' \
  "$(replace "$(replace "$BASE" 'opt=[]' 'opt=[from_cli]')" \
  'optdef=[optdef_default]' 'optdef=[file_def]')" "$out"

printf 'PROG_opts_opt=0\n' > "$JUNONIA_CONFIG"
run_app opts
check 'config file numeric zero is used' \
  "$(replace "$BASE" 'opt=[]' 'opt=[0]')" "$out"

: > "$JUNONIA_CONFIG"

# A repeatable option collects every value, separated by the unit separator.
unit="$(printf '\037')"
run_app opts first -multi a -multi b -multi c
check 'repeatable option' \
  "$(replace "$(replace "$BASE" 'multi=[]' "multi=[a${unit}b${unit}c]")" \
  'pos1=[]' 'pos1=[first]')" "$out"

run_app opts -multi a -multi b
check 'repeatable option, no positional' \
  "$(replace "$BASE" 'multi=[]' "multi=[a${unit}b]")" "$out"

# A program iterates the collected values using the documented separator.
run_app multi -many a -many b -many c
check 'repeatable option iterates with JUNONIA_US' \
  'many=[a]
many=[b]
many=[c]' "$out"

run_app seps
check 'separator variables are as documented' \
  'JUNONIA_US=1f
JUNONIA_FS=1c
JUNONIA_RS=1e
JUNONIA_GS=1d' "$out"

# Error handling.
run_app opts -bogus 1
check_contains 'unknown option' "$out" 'unknown option: -bogus'

run_app opts extra1 extra2
check_contains 'too many positional parameters' "$out" 'unknown parameter'

run_app opts -opt value extra1
check_contains 'positional parameters must precede options' "$out" \
  'all positional parameters must precede all options'

# A subcommand that is not documented at all is an unknown parameter.
run_app nosuchsub
check_contains 'undocumented subcommand' "$out" 'unknown parameter: nosuchsub'

# A documented subcommand with no implementation must report and exit. These
# run under a watchdog, because the failure mode is spinning, not reporting.
check_exits_quickly() {
  desc="$1"
  expect_msg="$2"
  shift 2
  clear_prog_env
  ( cd "$app" && ./prog "$@" > "$sandbox/slow.out" 2>&1 ) &
  running=$!
  waited=0
  while [ $waited -lt 5 ]; do
    sleep 1
    kill -0 $running 2>/dev/null || break
    waited=$((waited + 1))
  done
  if kill -0 $running 2>/dev/null; then
    kill -9 $running 2>/dev/null
    check "$desc" 'reports an error' 'still running after 5s'
  else
    check_contains "$desc" "$(cat "$sandbox/slow.out")" "$expect_msg"
  fi
}

check_exits_quickly 'documented, no implementation' \
  'command not found: prog_ghost' ghost

check_exits_quickly 'implementation without function' \
  'command not found: prog_missing' missing

###
### JSON options
###
### A documented boolean default belongs in the body whether it is true or
### false, so that the key exists for the API. A boolean with no default is
### left out until it is given, because for a PATCH, absent means leave alone.

printf '\n### JSON options\n'

if command -v jq >/dev/null 2>&1; then
  clear_prog_env
  run_in "$app" ./prog json
  check 'json: documented defaults, true and false' \
    'json=[{"enabled":true,"disabled":false,"nick":"nicko"}]
argc=2
shared=[shared_default]
plain=[pp]' "$out"

  clear_prog_env
  run_in "$app" ./prog json .bare
  check_contains 'json: flag with no default is absent until given' "$out" \
    '"bare":true'

  clear_prog_env
  run_in "$app" ./prog json .enabled false
  check_contains 'json: cli false beats a default of true' "$out" \
    '"enabled":false'

  clear_prog_env
  run_in "$app" ./prog json .disabled true
  check_contains 'json: cli true beats a default of false' "$out" \
    '"disabled":true'

  clear_prog_env
  run_in "$app" ./prog json .name bob
  check_contains 'json: string value' "$out" '"name":"bob"'

  # The same spellings of true and false as everywhere else; anything else is
  # an error rather than a JSON string in the body.
  run_app json .enabled 0
  check_contains 'json: cli zero is false' "$out" '"enabled":false'

  run_app json .disabled 1
  check_contains 'json: cli one is true' "$out" '"disabled":true'

  run_app json .enabled maybe
  check_contains 'json: cli value must be a boolean' "$out" \
    'option .enabled argument must be omitted (true)'
  check 'json: cli value must be a boolean, status' '1' "$rc"

  clear_prog_env
  run_in "$app" env PROG_json_enabled=false ./prog json
  check_contains 'json: environment variable' "$out" '"enabled":false'

  clear_prog_env
  printf 'PROG_json_disabled=true\n' > "$JUNONIA_CONFIG"
  run_in "$app" ./prog json
  check_contains 'json: configuration file' "$out" '"disabled":true'

  : > "$JUNONIA_CONFIG"

  clear_prog_env
  run_in "$app" ./prog json .bare .name bob
  check 'json: takes no argument slot' \
    'argc=2
shared=[shared_default]
plain=[pp]' "$(printf '%s\n' "$out" | tail -n +2)"
else
  printf '# jq is not installed, skipped JSON option tests\n'
fi

###
### Web layer
###
### A program picks its own curlrc after initialization, so JW_CURLRC stays
### writable, and that curlrc has to reach curl.

printf '\n### web layer\n'

if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  wapp="$sandbox/wprog"
  mkdir -p "$wapp/doc" "$sandbox/stub"

  # junonia looks for junonia_web beside the program.
  cp "$root/junonia_web" "$wapp/junonia_web"

  # A curl that records its arguments rather than making a request.
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$WPROG_STUB"\n' \
    > "$sandbox/stub/curl"
  chmod +x "$sandbox/stub/curl"
  printf 'header = "X-Token: stub"\n' > "$sandbox/curlrc"

  cat > "$wapp/doc/wprog.md" <<'MDEOF'
## `wprog`

Report how the web layer initialized and what curl was given.

### Synopsis

    wprog [SUBCOMMAND]
MDEOF

  cat > "$wapp/wprog" <<'WEOF'
#!/bin/sh
wprog () {
  echo "init=${JW_INIT:-unset}"
  if [ -n "$JW_DEFAULT_CURLRC" ]; then
    echo 'default_curlrc=set'
  else
    echo 'default_curlrc=unset'
  fi

  # In a subshell: assigning a readonly variable ends a non-interactive shell.
  if ( JW_CURLRC="$JW_DEFAULT_CURLRC/program" ) 2>/dev/null; then
    echo 'assign=ok'
  else
    echo 'assign=refused'
  fi

  rm -f "$WPROG_STUB"
  junonia_request http://junonia.invalid/ >/dev/null 2>&1
  [ -f "$WPROG_STUB" ] && sed 's/^/curl saw: /' "$WPROG_STUB"
}
junonia_bootstrap () {
  JUNONIA_TARGET="$0"
  JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
  JUNONIA_TARGET="$JUNONIA_PATH/$(basename "$JUNONIA_TARGET")"
}
junonia_bootstrap
. "$JUNONIA_ROOT/junonia"
junonia_run "$@"
WEOF
  chmod +x "$wapp/wprog"

  clear_prog_env
  run_in "$wapp" env PATH="$sandbox/stub:$PATH" \
    WPROG_STUB="$sandbox/stub/args" JW_CURLRC="$sandbox/curlrc" ./wprog

  check_contains 'web: web layer initialized' "$out" 'init=1'
  check_contains 'web: web layer default curlrc' "$out" 'default_curlrc=set'
  check_contains 'web: program may set JW_CURLRC after initialization' \
    "$out" 'assign=ok'
  check_contains 'web: the curlrc reaches curl' "$out" \
    "curl saw: -s -w \\nhttp_code: %{http_code}\\n --config $sandbox/curlrc"
else
  printf '# jq or curl not installed, skipped web layer checks\n'
fi

###
### Part three: argument resolution, spec string driven
###
### Same matrix, different path through junonia. The comments in the spec are
### what the help command renders, and must be ignored while resolving values
### at any indentation.

printf '\n### argument resolution (spec string)\n'

sapp="$sandbox/sprog"
mkdir -p "$sapp"
cat > "$sapp/prog" <<'SPECEOF'
#!/bin/sh
prog () {
  echo "prog: shared=[$1]"
}

prog_opts () {
  echo "shared=[$1]"
  echo "opt=[$2]"
  echo "optdef=[$3]"
  echo "flag=[$4]"
  echo "flag_one=[$5]"
  echo "flag_false=[$6]"
  echo "flag_true=[$7]"
  echo "flag_zero=[$8]"
  echo "xray=[${9}]"
  echo "yflag=[${10}]"
}

spec='# A program configured by a spec string.
#
# Comments like these are shown by help and ignored when resolving arguments.

prog
  -shared SHARED=shared_default
  opts
    -opt OPT
    -optdef OPTDEF=optdef_default
    -flag
    -flag-one=1
    -flag-false=false
    -flag-true=true
    -flag-zero=0
    -x, -xray XRAY=xray_default
    -y, -yflag
'

junonia_bootstrap () {
  JUNONIA_TARGET="$0"
  JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
  JUNONIA_TARGET="$JUNONIA_PATH/$(basename "$JUNONIA_TARGET")"
}
junonia_bootstrap
. "$JUNONIA_ROOT/junonia"
junonia_runspec "$spec" "$@"
SPECEOF
chmod +x "$sapp/prog"

run_sprog() {
  run_with "$sapp" "$@"
}

SBASE='shared=[shared_default]
opt=[]
optdef=[optdef_default]
flag=[]
flag_one=[1]
flag_false=[]
flag_true=[1]
flag_zero=[]
xray=[xray_default]
yflag=[]'

run_sprog opts
check 'spec: all defaults' "$SBASE" "$out"

run_sprog opts -opt given
check 'spec: option value' "$(replace "$SBASE" 'opt=[]' 'opt=[given]')" "$out"

run_sprog opts -flag
check 'spec: flag given' "$(replace "$SBASE" 'flag=[]' 'flag=[1]')" "$out"

# A hand written spec separates aliases with a comma and a space, which gives
# each name its own field: the alias must still be reachable, and the second
# name of an aliased flag must not be read as the value it takes.
run_sprog opts -x byfirst
check 'spec: aliased option by its first name' \
  "$(replace "$SBASE" 'xray=[xray_default]' 'xray=[byfirst]')" "$out"

run_sprog opts -xray byalias
check 'spec: aliased option by its alias' \
  "$(replace "$SBASE" 'xray=[xray_default]' 'xray=[byalias]')" "$out"

run_sprog opts -y
check 'spec: aliased flag is a flag' \
  "$(replace "$SBASE" 'yflag=[]' 'yflag=[1]')" "$out"

run_sprog opts -yflag
check 'spec: aliased flag by its alias' \
  "$(replace "$SBASE" 'yflag=[]' 'yflag=[1]')" "$out"

run_sprog opts -y false
check 'spec: aliased flag given false' "$SBASE" "$out"

run_sprog opts -flag-false
check 'spec: false default, flag given' \
  "$(replace "$SBASE" 'flag_false=[]' 'flag_false=[1]')" "$out"

run_sprog opts -flag-true false
check 'spec: true default, set false' \
  "$(replace "$SBASE" 'flag_true=[1]' 'flag_true=[]')" "$out"

run_sprog opts -flag maybe
check_contains 'spec: invalid boolean' "$out" \
  'argument must be omitted (true) or one of'

run_sprog PROG_opts_opt=from_env opts
check 'spec: environment option' \
  "$(replace "$SBASE" 'opt=[]' 'opt=[from_env]')" "$out"

printf 'PROG_opts_opt=from_file\n' > "$JUNONIA_CONFIG"
run_sprog opts
check 'spec: config file option' \
  "$(replace "$SBASE" 'opt=[]' 'opt=[from_file]')" "$out"
: > "$JUNONIA_CONFIG"

###
### Part four: help output
###

printf '\n### help\n'

run_app help
check_contains 'help: name line' "$out" \
  'prog -- Test program for the junonia smoke tests.'
check_contains 'help: subcommand listing' "$out" 'opts'
check_contains 'help: option documentation' "$out" \
  'An option shared by every subcommand.'
check_contains 'help: metacommands' "$out" 'version'

run_app opts help
check_contains 'help: subcommand, trailing help' "$out" 'prog opts --'

run_app help opts
check_contains 'help: subcommand, leading help' "$out" 'prog opts --'

# Help may be asked for before or after the subcommands, and to any depth.
run_app nest deep help
check_contains 'help: nested subcommand name' "$out" 'prog nest deep --'
check_contains 'help: nested subcommand option' "$out" '-deep-opt'
check_contains 'help: nested subcommand description' "$out" 'Nothing to see here'

run_app help nest deep
check_contains 'help: nested, leading help' "$out" 'prog nest deep --'

run_app nest help deep
check_contains 'help: nested, help in the middle' "$out" 'prog nest deep --'

run_app help nest
check_contains 'help: parent lists its subcommands' "$out" 'deep'
check_contains 'help: parent lists its options' "$out" '-nest-opt'

# Option aliases appear in the help and work on the command line.
run_app nest help
check_contains 'help: option aliases' "$out" 'nest-opt'

run_app nest -nest-opt n
check 'option by its name' 'shared=[shared_default] nest_opt=[n]' "$out"

run_app nest -n n
check 'option by its alias' 'shared=[shared_default] nest_opt=[n]' "$out"

run_app nest
check 'option default is used' 'shared=[shared_default] nest_opt=[nest_default]' "$out"

# The whole path is documented, so the parent options of a nested subcommand
# are resolved and passed along just like any other.
run_app nest deep -deep-opt v
check 'nested subcommand runs' \
  'shared=[shared_default] nest_opt=[nest_default] deep_opt=[v]' "$out"

# Options of every command on the path may be given after the full subcommand
# path, which is required: positional parameters all precede options.
run_app nest deep -nest-opt n -deep-opt v
check 'nested subcommand runs with parent option' \
  'shared=[shared_default] nest_opt=[n] deep_opt=[v]' "$out"

run_sprog help
check_contains 'spec help: comments' "$out" \
  'Comments like these are shown by help'
check_contains 'spec help: options' "$out" '-flag-one'

###
### Part five: caching and config file editing
###
### Cached artifacts are a classic source of "works until it is cached" bugs,
### and the spec that gets cached is the same spec these tests exercise.

printf '\n### caching and config editing\n'

: > "$JUNONIA_CONFIG"
rm -rf "$JUNONIA_CACHEDIR"
mkdir -p "$JUNONIA_CACHEDIR"

run_app JUNONIA_CACHE=1 opts
check 'cache: uncached run' "$BASE" "$out"
check 'cache: spec written' 'yes' \
  "$([ -f "$JUNONIA_CACHEDIR/spec" ] && echo yes || echo no)"

run_app JUNONIA_CACHE=1 opts
check 'cache: cached run' "$BASE" "$out"

run_app JUNONIA_CACHE=1 opts first -flag
check 'cache: cached run with values' \
  "$(replace "$(replace "$BASE" 'pos1=[]' 'pos1=[first]')" 'flag=[]' 'flag=[1]')" "$out"

run_app JUNONIA_CACHE=1 help
check_contains 'cache: help still rendered' "$out" 'prog -- Test program'
run_app JUNONIA_CACHE=1 help
check_contains 'cache: help from cache' "$out" 'prog -- Test program'

run_app JUNONIA_CACHE=1 cache -clear
check 'cache: cleared' 'no' \
  "$([ -f "$JUNONIA_CACHEDIR/spec" ] && echo yes || echo no)"

# The config subcommand displays the configuration file, and takes the same
# subcommand, options, and values as a normal invocation in order to write them.
run_app config opts -opt cfg_value
check_contains 'config: writes option' "$(cat "$JUNONIA_CONFIG")" \
  'PROG_opts_opt="cfg_value"'

run_app opts
check 'config: written value is used' \
  "$(replace "$BASE" 'opt=[]' 'opt=[cfg_value]')" "$out"

run_app config
check_contains 'config: displays file' "$out" 'PROG_opts_opt="cfg_value"'

# An option given to config with no value removes the entry.
run_app config opts -opt
check 'config: option removed from file' 'no' \
  "$(grep -q '^PROG_opts_opt=' "$JUNONIA_CONFIG" && echo yes || echo no)"

run_app opts
check 'config: removed value no longer used' "$BASE" "$out"

: > "$JUNONIA_CONFIG"

###
### Summary
###

printf '\n'
if [ $n_fail -eq 0 ]; then
  printf '%s: all %d checks passed\n' "$me" "$n_tests"
  exit 0
fi
printf 'failed checks:%s\n' "$failures"
printf '%s: %d of %d checks FAILED\n' "$me" "$n_fail" "$n_tests"
[ "$verbose" = 1 ] || printf '(re-run with -v for details)\n'
exit 1
