#!/bin/sh

junonia_web () {
  _junonia_cmds="  -curlrc CURLRC=$JUNONIA_CONFIGDIR/curlrc
  -oauth OAUTH
  -basic-auth USER:PASSWORD
$_junonia_cmds
  "

  readonly JW_INIT=1
  export JW_INIT
}

##
## Utility function declarations
##

# Pretty print JSON as text with each key/value on a single line and no
# brackets, quotes, or other formatting.
jw_tree_print () {
  # $1: JSON body
  # $2: Optional selector for jq to make the root

  # If a selector was given, select that as the root, otherwise take everything
  if [ -n "$2" ]; then
    if ! jw_tree_root="$(printf '%s' "$1" | jq -r "$2")"; then
      echo "unable to select object(s) using $2"
    fi
  else
    jw_tree_root="$1"
  fi

  echodebug ""
  echodebug_raw '%s\n' "$1"
  if jw_json_tree="$(printf '%s' "$jw_tree_root" | jq -r '
    def leaf_print(json):
      json.indent  as $i  |
      $i + "  "    as $ni |
      json.element as $e  |
        (select(($e | type) != "array" and ($e | type) != "object") |
          "\($e)"),
        (select(($e | type) == "object" or ($e | type) == "array") |
          $e | keys[] as $k |
          "\($k):",
          "\(leaf_print({"element": $e[$k], "indent": $ni}))");

    leaf_print({"element": ., "indent": ""})')"; then
    echo "$jw_json_tree"
  else
    echo "not a JSON object:"
    echo "$1"
    return 1
  fi
}

# Perform a curl using the configured authentication and given options.
# Optionally supply a number and jq selector to retrieve additional pages.
# Usage:
#
# Perform one page request and return the result
# jq_request <curl url and options>
#
# Perform a page request and get pages using the selected url up to a default
# jq_request <jq selector> <curl url and options>
#
# Perform a page request and get pages using the selected url up to a limit
# jq_request <integer pages to retrieve> <jq selector> <curl url and options>
#
# Perform a page request and get next pages using a callback
# jq_request <function name> <curl url and options>
#
jw_request () {
  echodebug "jw_request args: $@"

  # Was a page limit provided?
  if [ "$1" -eq "$1" ] >/dev/null 2>&1; then
    echodebug "page limit is $1"
    npages="$1"
    shift

    # If 0 was supplied get all the pages using a very large number
    if [ $npages = 0 ]; then
      echodebug "getting all pages due to page limit 0"
      npages=100000
    fi
  fi

  # Was a selector provided?
  if [ -z "${1##.*}" ]; then
    echodebug "selector provided for paging: $1"
    selector="$1"
    shift

    # Get all the pages using a very large number
    if [ -z "$npages" ]; then
      echodebug "selector provided but no page limit, so getting all pages"
      npages=100000
    fi
  fi

  # Was a callback supplied?
  echodebug "checking to see if "$1" is a callback"
  if [ junonia_require_cmds "$1" 2>/dev/null ]; then
    echodebug "found callback command"
    callback="$1"
    shift
  fi

  # No page limit, no selector. Get one page.
  if [ -z "$npages" ] && [ -z "$selector" ]; then
    echodebug "options specify getting a single page"
    npages=1
  fi

  echodebug "npages:   $npages"
  echodebug "selector: $selector"
  echodebug "callback: $callback"
  echodebug "curl args: $@"
 
  if [ "$npages" -lt 1 ]; then
    return 0
  fi

  case $JW_CURL_AUTH_SRC in
    curlrc)
      echovvv "curl --header \"Content-Type: $JW_CONTENT_TYPE\"" >&2
      echovvv "     --config \"$JW_CURLRC\"" >&2
      echovvv "     $*" >&2

      resp="$(curl $curl_silent -w '\nhttp_code: %{http_code}\n' \
                   --header "Content-Type: $JW_CONTENT_TYPE" \
                   --config "$curlrc" \
                   $@)"
      ;;
    oauth)
      echovvv "curl --header \"Content-Type: $JW_CONTENT_TYPE\"" >&2
      echovvv "     --header \"Authorization: Bearer \$JW_CURL_OAUTH\"" >&2
      echovvv "     $*" >&2

      resp="$(curl $curl_silent -w '\nhttp_code: %{http_code}\n' \
                   --header "Content-Type: $JW_CONTENT_TYPE" \
                   --header "Authorization: Bearer $JW_OAUTH" \
                   $@)"
      ;;
    basic_auth)
      echovvv "curl --header \"Content-Type: $JW_CONTENT_TYPE\"" >&2
      echovvv "     --user \"$JW_CURL_BASIC\"" >&2
      echovvv "     $*" >&2

      resp="$(curl $curl_silent -w '\nhttp_code: %{http_code}\n' \
                   --header "Content-Type: $JW_CONTENT_TYPE" \
                   --user "$JW_CURL_BASIC" \
                   $@)"
      ;;
  esac

  resp_body="$(printf '%s' "$resp" | awk '!/^http_code/; /^http_code/{next}')"
  resp_code="$(printf '%s' "$resp" | awk '!/^http_code/{next} /^http_code/{print $2}')"

  echodebug "API request http code: $resp_code. Response:"
  echodebug_raw "$resp_body"

  case "$resp_code" in
    2*)
      # Output the response here
      printf "%s" "$resp_body"

      if [ -n $selector ]; then
        next_page="$(printf "%s" "$resp_body" | \
                     jq -r "$selector" 2>&3)"
      elif [ -n $callback ]; then
        next_page="$($callback "$resp_code" "$resp_body")"
      else
      fi

      if [ -n "$next_page" ] && [ "$next_page" != null ] &&
         ! [ "$npages" -le 1 ]; then
        echodebug "next page: $next_page"
        echodebug "npages: $npages"
        next_link="$(printf "%s" "$resp_body" | jq -r "$selector")"
        echodebug "next link: $next_link"
        jw_request $((--npages)) "$selector" "$next_link"
      fi
      ;;
    4*|5*)
      echoerr "API request failed."
      echoerr_raw "HTTP status code: $resp_code"
      if json_err="$(jw_tree_print "$resp_body" "$JW_ERR_SELECTOR")"; then
        echoerr_raw "Details:"
        echoerr_raw "$json_err"
      else
        echoerr "Response:"
        echoerr_raw "$resp_body"
      fi

      return 1
      ;;
    *)
      echoerr "Unable to complete API request."
      echoerr "HTTP status code: $resp_code."
      echoerr "Response:"
      echoerr "$resp_body"
      return 1
      ;;
  esac
}

_jw_filter () {
  readonly JW_DEFAULT_CURLRC="$JUNONIA_CONFIGDIR/curlrc"

  JW_CURLRC="${1:-"$JW_DEFAULT_CURLRC"}"
  readonly JW_OAUTH="$2"
  readonly JW_BASIC_AUTH="$3"

  JW_CURL_AUTH_SRC=none

  if [ -f "$curlrc" ]; then
    JW_CURL_AUTH_SRC=curlrc
  fi

  readonly JW_CURLRC

  echodebug "JW_CURLRC:     $JW_CURLRC"
  echodebug "JW_OAUTH:      $JW_OAUTH"
  echodebug "JW_BASIC_AUTH: $JW_BASIC_AUTH"

  # OAuth at the command line takes second highest precedence
  if [ -z "$JW_CURL_AUTH_SRC" ] && [ -n "$JW_OAUTH" ] &&
     echo "$JUNONIA_ARGS" | grep -qE -- ' -oauth '; then
     echodebug "explicit -oauth"
     JW_CURL_AUTH_SRC=oauth
  fi

  # Basic auth at the command line takes third highest precedence
  if [ -z "$JW_CURL_AUTH_SRC" ] && [ -n "$JW_BASIC_AUTH" ] &&
     echo "$JUNONIA_ARGS" | grep -qE -- ' -basic-auth '; then
     echodebug "explicit -basic-auth"
     JW_CURL_AUTH_SRC=basic
  fi

  # curlrc from any source (default included) comes fourth
  if [ -z "$JW_CURL_AUTH_SRC" ] && [ -f "$JW_CURLRC" ]; then
    echodebug "curlrc from env and config file"
    JW_CURL_AUTH_SRC=curlrc
  fi

  if [ -z "$JW_CURL_AUTH_SRC" ]; then
  fi

  case $JW_CURL_AUTH_SRC in
    curlrc)
      echodebug "basic:     $token_status, unused"
      echodebug "curlrc:    $curlrc"
      ;;
    oauth)
      echodebug "token:     $token_status"
      echodebug "curlrc:    $curlrc, unused"
      ;;
    basic)
      echodebug "token:     $token_status"
      echodebug "curlrc:    $curlrc, unused"
      ;;
    curlrc_not_found)
      echodebug "token:     $token_status, unused"
      echodebug "curlrc:    $curlrc specified but not found"
      ;;
    none)
      echodebug "token:     empty"
      echodebug "curlrc:    $curlrc not found"
      ;;
  esac

  readonly JW_CURLRC="$1"
  readonly JW_OAUTH="$2"
  readonly JW_BASIC_AUTH="$3"

  return 9
}

