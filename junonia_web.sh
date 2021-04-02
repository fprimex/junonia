#!/bin/sh

###
### Execution environment setup and management
###

jw_init () {
  echodebug "begin jw init"

  if [ -n "$JW_INIT" ]; then
    # init has already been run
    return
  fi

  if ! junonia_require_cmds jq curl; then
    return 1
  fi

  if [ -z "$JUNONIA_DEBUG" ]; then
    JW_CURL_SILENT="-s"
  fi

  readonly JW_DEFAULT_CURLRC="$JUNONIA_CONFIGDIR/curlrc"
  readonly JW_CURLRC="${JW_CURLRC:-"$JW_DEFAULT_CURLRC"}"

  JW_AUTH_SRC=
  if [ -n "$JW_AUTH" ]; then
    JW_AUTH_SRC=env
    echodebug "explicit curl auth provided: $JW_AUTH"
  else
    if [ -f "$JW_CURLRC" ]; then
      JW_AUTH_SRC=curlrc
      echodebug "authenticating curl with curlrc $JW_CURLRC"
      JW_AUTH="--config $JW_CURLRC"
    elif [ -n "$JW_OAUTH" ]; then
      JW_AUTH_SRC=oauth
      echodebug "authenticating curl with oauth token"
      JW_AUTH="--oauth2-bearer $JW_OAUTH"
    elif [ -n "$JW_BASIC" ]; then
      JW_AUTH_SRC=basic
      echodebug "authenticating curl with basic login info"
      JW_AUTH="--user $JW_BASIC"
    fi
  fi

  # Indicate that init has happened
  readonly JW_INIT=1
}


###
### jq utility functions
###

# Recursively print a JSON object as indented plain text.
# Call by including in a jq program and sending an object and starting indent:
# leaf_print({"SOME TITLE": .any_attr, "indent": "  "})
jw_jq_leafprint='
  def leaf_print(o):
    o.indent as $i |
    $i + "  " as $ni |
    o.errors as $e |
    $e | keys[] as $k |
      (select(($e[$k] | type) != "array" and ($e[$k] | type) != "object") |
        "\($k): \($e[$k])"),
      (select(($e[$k] | type) == "object") |
        "\($k):",
        "\(leaf_print({"errors": $e[$k], "indent": $ni}))"),
      (select(($e[$k] | type) == "array") |
        "\($k):",
        "\(leaf_print({"errors": $e[$k], "indent": $ni}))");
'

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

junonia_web () {
  func_name="$1"
  shift
  method="$1"
  shift
  content_t="$1"
  shift
  url="$1"
  shift

  echodebug "junonia_web $func_name $method $url"

  # Determine how many upper case parameters there are to replace in the url
  n_opts="$(echo "$url" | awk '{print gsub(/{[-_\.A-Z]+}/,"")}')"

  # See if there are additional parameters coming from elsewhere.
  if [ -n "$JW_ADDL_PARAMS" ]; then
    echodebug "addl params: $JW_ADDL_PARAMS"
    url="$(echo "$url" | awk -v "JRS=$JUNONIA_RS" -v "params=$JW_ADDL_PARAMS" '{
      split(params, addl_params, JRS)
      for(p in addl_params) {
        split(addl_params[p], a, "=")
        did_sub = sub("{" a[1] "}", a[2])
        subs = subs + did_sub
      }
      print
      exit subs
    }')"
    addl_subs=$?
  else
    addl_subs=0
  fi

  # Remove the number of upper case parameters replaced by addl parameters
  n_opts=$(( $n_opts - $addl_subs ))

  # For that many options, shift off values and substitute the parameter.
  # Parameters are of the form FOO=bar, where FOO is always uppercase.
  i=0
  n_subs=0
  while [ $i -lt $# ] && [ $i -lt $n_opts ]; do
    url="$(echo "$url" | awk -v "param=$1" '{
      split(param, a, "=")
      did_sub = sub("{" a[1] "}", a[2])
      print
      exit did_sub
    }')"
    n_subs=$(( $n_subs + $? ))
    i=$(( $i+1 ))
    shift
  done

  if [ "$n_subs" -lt "$n_opts" ]; then
    echoerr "Mismatch on number of parameters and url"
    echoerr "Cannot continue with $url"
    return 1
  fi

  echodebug "final url: $url"

  echodebug "remaining arguments ($#):"
  echodebug_raw $@
  i=0
  query=
  while [ $i -le $# ]; do
    if [ -n "${1#*=}" ]; then
      query="$query&$1"
    fi
    i=$(( $i+1 ))
    shift
  done
  echodebug "remaining arguments ($#):"
  echodebug_raw $@

  if [ -n "$JW_ADDL_OPTIONS" ]; then
    query="$query&$JW_ADDL_OPTIONS"
  fi

  if [ -n "$query" ]; then
    query="?${query#?}"
  fi

  echodebug "final query: $query"

  if _junonia_load_func $func_name; then
    echodebug "located callback $func_name"
    cb=$func_name
  elif command -v ${JUNONIA_NAME}_jw_callback >/dev/null 2>&1; then
    echodebug "global callback ${JUNONIA_NAME}_jw_callback present"
    cb=${JUNONIA_NAME}_jw_callback
  else
    echodebug "no callback found"
    cb=
  fi

  echodebug "JW_JSON:"
  echodebug_raw "$JW_JSON"

  case "$method" in
    POST|PUT|PATCH)
      if [ -n "$cb" ]; then
        echodebug "making $method request with callback $cb"
        $cb "$(jw_request "$method" "$JW_JSON" "$content_t" "$url$query")"
      else
        echodebug "making $method request without callback"
        jw_request "$method" "$JW_JSON" "$content_t" "$url$query"
      fi
      ;;
    *)
			if [ -n "$cb" ]; then
				echodebug "making $method request with callback $cb"
				$cb "$(jw_request "$method" "$content_t" "$url$query")"
			else
				echodebug "making $method request without callback"
				jw_request "$method" "$content_t" "$url$query"
			fi
  esac
}

# Perform a curl using the configured authentication and given options.
# Optionally supply a number and jq selector to retrieve additional pages.
# Usage:
#
# Perform one page request and return the result
# jq_request <method> <method specific options> <curl url and options>
#
# Perform a page request and get pages using the selected url up to a default
# jq_request <jq selector> <method> <method specific options> \
#            <curl url and options>
#
# Perform a page request and get pages using the selected url up to a limit
# jq_request <integer pages to retrieve> <jq selector> <method> \
#            <method specific options> <curl url and options>
#
# Perform a page request and get next pages using a callback
# jq_request <paging function name> <method> <method specific options> \
#            <curl url and options>
#
# npages                         = error
#           selector             = use selector, get all pages 
#                       callback = use callback
# npages && selector             = use selector, get exactly npages
# npages &&             callback = error
#           selector && callback = error
# 
# jw_request [method [payload]] [content_t] url
#            [npages] [selector] [callback] [curl options]
jw_request () {
  echodebug "jw_request args: $@"

  _method=
  _url=
  _content_t=
  _payload=
  _npages=
  _selector=
  _callback=

  case "$1" in
    GET|HEAD|DELETE|CONNECT|OPTIONS|TRACE)
      _method="$1"
      shift
      echodebug "no special processing required for method $_method"
      ;;
    POST|PUT|PATCH)
      _method="$1"
      shift
      _payload="$1"
      shift
      if [ -z "$_payload" ]; then
        echodebug "WARNING: EMPTY PAYLOAD"
        # Not going to error. I have seen weirder things than requiring
        # an empty _payload on a POST.
      fi
      ;;
    http*)
      _method=GET
      _url="$1"
      shift
      ;;
  esac

  if [ -z "$_url" ]; then
    _content_t="$1"
    shift

    _url="$1"
    shift
  fi

  if [ -z "$_content_t" ]; then
    _content_t="${JW_CONTENT_TYPE:-"application/octet-stream"}"
  fi

  # Was a page limit provided?
  if [ "$1" -eq "$1" ] >/dev/null 2>&1; then
    echodebug "page limit is $1"
    _npages="$1"
    shift

    # If 0 was supplied get all the pages using a very large number
    if [ $_npages = 0 ]; then
      echodebug "getting all pages due to page limit 0"
      _npages=100000
    fi
  fi

  # Was a _selector provided?
  if [ -z "${1##.*}" ]; then
    echodebug "selector provided for paging: $1"
    _selector="$1"
    shift
  fi

  # Was a _callback supplied?
  echodebug "checking to see if "$1" is a callback"
  if [ junonia_require_cmds "$1" 2>/dev/null ]; then
    echodebug "found callback command $1"
    _callback="$1"
    shift
  fi

  echodebug "method:   $_method"
  echodebug "url:      $_url"
  echodebug "npages:   $_npages"
  echodebug "selector: $_selector"
  echodebug "callback: $_callback"
  echodebug "remaining args to curl: $@"
  echodebug "payload:"
  echodebug_raw "$_payload"

  case -$_npages:$_selector:$_callback- in
  -::-)
    echodebug "no page limit, no selector, no callback"
    echodebug "will make the single request"
    ;;
  -?*::-)
    echodebug "npages"
    echoerr "page limit given but no selector or callback for request"
    return 1
    ;;
  -:?*:-)
    echodebug "selector only, will get all pages"
    _npages=100000
    echodebug "updated npages:   $_npages"
    ;;
  -::?*-)
    echodebug "callback only, will get all pages"
    _npages=100000
    echodebug "updated npages:   $_npages"
    ;;
  -?*:?*:-)
    echodebug "npages, selector, will get exact pages"
    ;;
  -?*::?*-)
    echodebug "npages, callback"
    echoerr "when using a callback it has explicit control over pagination"
    echoerr "page limit given, which conflicts with callback"
    return 1
    ;;
  -:?*:?*-|-?*:?*:?*-)
    echodebug "selector, callback"
    echoerr "selector and callback both specified for request"
    return 1
    ;;
  esac

  if [ -n "$_npages" ] && [ "$_npages" -lt 1 ]; then
    return 0
  fi

  case "$JW_AUTH_SRC" in
    curl)
      _autharg="$JW_AUTH"
      ;;
    oauth)
      _autharg='--oauth2-bearer $TOKEN_REDACTED'
      ;;
    basic)
      _autharg='--user $user@$password_REDACTED'
    ;;
    env)
      _autharg='$JW_AUTH'
      ;;
  esac

  echovvv "curl --header \"Content-Type: $_content_t\"" >&2
  if [ -n "$_autharg"]; then
    echovvv "$_autharg"
  fi
  if [ -n "$_payload" ]; then
    echovvv "--data \"$_payload\""
  fi
  echovvv "     $*" >&2

  if [ -z "$_payload" ]; then
    _resp="$(curl $JW_CURL_SILENT -w '\nhttp_code: %{http_code}\n' \
                  $_autharg \
                  "$_url" \
                  $@)"
  else
    _resp="$(curl $JW_CURL_SILENT -w '\nhttp_code: %{http_code}\n' \
                  $_autharg \
                  --data "$_payload" \
                  "$_url" \
                  $@)"
  fi

  echodebug "curl output:"
  echodebug_raw "$_resp"

  _resp_body="$(printf '%s' "$_resp" | awk '!/^http_code/; /^http_code/{next}')"
  _resp_code="$(printf '%s' "$_resp" | awk '!/^http_code/{next} /^http_code/{print $2}')"
  JW_LAST_RESP_CODE="$_resp_code"

  echodebug "extracted response code: $_resp_code"
  echodebug "extracted response:"
  echodebug_raw "$_resp_body"

  case "$_resp_code" in
    2*)
      # Output the response here
      printf "%s" "$_resp_body"

      if [ -n "$_selector" ]; then
        echodebug "selector"
        _next_page="$(printf "%s" "$_resp_body" | \
                      jq -r "$_selector" 2>&3)"
        echodebug "next page: $next_page"
      elif [ -n "$_callback" ]; then
        echodebug "callback"
        _next_page="$($_callback "$_resp_code" "$_resp_body")"
      else
        echodebug "no callback, no selector in jq_request"
      fi

      if [ -n "$_next_page" ] && [ "$_next_page" != null ] &&
         ! [ "$_npages" -le 1 ]; then
        echodebug "next link: $_next_link"
        echodebug "_npages: $_npages (will be decremented by 1)"
        jw_request $((--_npages)) "$_selector" "$_next_page"
      fi
      ;;
    4*|5*)
      echoerr "API request failed."
      echoerr_raw "HTTP status code: $_resp_code"
      if json_err="$(jw_tree_print "$_resp_body" "$JW_ERR_SELECTOR")"; then
        echoerr_raw "Details:"
        echoerr_raw "$_json_err"
      else
        echoerr "Response:"
        echoerr_raw "$_resp_body"
      fi

      return 1
      ;;
    *)
      echoerr "Unable to complete API request."
      echoerr "HTTP status code: $_resp_code."
      echoerr "Response:"
      echoerr "$_resp_body"
      return 1
      ;;
  esac
}
