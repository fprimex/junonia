#!/bin/sh

##
## Utility function declarations
##

# Replace quotes and newlines with escape characters to prepare the
# value for insertion into JSON.
jw_escape_value () {
  printf '%s' "$1" | awk '
  {
    gsub(/"/,"\\\"")
    gsub(/\\n/,"\\\\n")
  }
  NR == 1 {
    value_line = $0
  }
  NR != 1 {
    value_line = value_line "\\n" $0
  }
  END {
    printf "%s", value_line
  }'
}

jw_request () {
  # $1: optional integer parameter for number of next-pages to retrieve
  # $1 or $2 to $#: arguments to provide to curl

  echodebug "tfh_api_call args: $@"

	if ! [ "$1" -eq "$1" ] >/dev/null 2>&1; then
    npages="10000"
  else
    npages="$1"
    shift
	fi

  echodebug "npages: $npages"
  echodebug "curl args: $@"
 
  if [ "$npages" -lt 1 ]; then
    return 0
  fi

  case $curl_token_src in
    curlrc)
      echovvv "curl --header \"Content-Type: application/vnd.api+json\"" >&2
      echovvv "     --config \"$curlrc\"" >&2
      echovvv "     $*" >&2

      resp="$(curl $curl_silent -w '\nhttp_code: %{http_code}\n' \
                   --header "Content-Type: application/vnd.api+json" \
                   --config "$curlrc" \
                   $@)"
      ;;
    token)
      echovvv "curl --header \"Content-Type: application/vnd.api+json\"" >&2
      echovvv "     --header \"Authorization: Bearer \$TFH_token\"" >&2
      echovvv "     $*" >&2

      resp="$(curl $curl_silent -w '\nhttp_code: %{http_code}\n' \
                   --header "Content-Type: application/vnd.api+json" \
                   --header "Authorization: Bearer $token" \
                   $@)"
      ;;
  esac

  resp_body="$(printf '%s' "$resp" | awk '!/^http_code/; /^http_code/{next}')"
  resp_code="$(printf '%s' "$resp" | awk '!/^http_code/{next} /^http_code/{print $2}')"

  echodebug "API request http code: $resp_code. Response:"
  echodebug_raw "$resp_body"

  case "$resp_code" in
    2*)
      printf "%s" "$resp_body"

      next_page="$(printf "%s" "$resp_body" | \
                   jq -r '.meta.pagination."next-page"' 2>&3)"

      if [ -n "$next_page" ] && [ "$next_page" != null ] &&
         ! [ "$npages" -le 1 ]; then
        echodebug "next page: $next_page"
        echodebug "npages: $npages"
        next_link="$(printf "%s" "$resp_body" | jq -r '.links.next')"
        echodebug "next link: $next_link"
        tfh_api_call $((--npages)) "$next_link"
      fi
      ;;
    4*|5*)
      echoerr "API request failed."
      echoerr_raw "HTTP status code: $resp_code"
      if jsonapi_err="$(echo "$resp_body" | jq -r '
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

        leaf_print({"errors": .errors[], "indent": "  "})')"; then
        echoerr_raw "JSON-API details:"
        echoerr_raw "$jsonapi_err"
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

check_required () {
  if [ 0 -eq $# ]; then
    check_for="org ws token address"
  else
    check_for="$*"
  fi

  missing=0
  for i in $check_for; do
    case "$i" in
      org)
        if [ -z "$org" ]; then
          missing=1
          echoerr 'TFE organization required.'
          echoerr 'Set with $TFH_org or use -org'
          echoerr
        fi
      ;;
      ws)
        if [ -z "$ws" ]; then
          missing=1
          echoerr 'TFE workspace name required.'
          echoerr 'Set with $TFH_name or use -name, and optionally -prefix'
          echoerr
        fi
      ;;
      token)
        if [ "$curl_token_src" = none ]; then
          missing=1
          echoerr 'TFE API token required.'
          echoerr 'Set with `tfh curl-config`,  $TFH_token, or -token'
          echoerr
        fi
      ;;
      address)
        # This really shouldn't happen. Someone would have to
        # explicitly pass in an empty string to the command line
        # argument.
        if [ -z "$address" ]; then
          missing=1
          echoerr 'TFE hostname required.'
          echoerr 'Set with -hostname or $TFH_hostname'
          echoerr
        fi
      ;;
    esac
  done
  return $missing
}

tfh_junonia_filter () {
  readonly TFH_DEFAULT_CURLRC="$JUNONIA_CONFIGDIR/curlrc"

  readonly org="$1"
  readonly name="$2"
  readonly prefix="$3"
  readonly token="$4"
  readonly curlrc="${5:-"$TFH_DEFAULT_CURLRC"}"
  readonly hostname="$6"

  # Waterfall verbosity levels down
  readonly vvverbose="$9"
  readonly vverbose="${8:-$vvverbose}"
  readonly verbose="${7:-$vverbose}"

  readonly address="https://$hostname"
  readonly ws="$prefix$name"

  echov "org:       $org"
  echov "prefix:    $prefix"
  echov "workspace: $name"
  echov "hostname:  $hostname"
  echov "address:   $address"
  echov "verbose:   $verbose"
  echov "vverbose:  $vverbose"
  echov "vvverbose: $vvverbose"

  curl_token_src=

  # curlrc argument at the command line takes highest precedence
  if echo "$TFH_CMDLINE" | grep -qE -- '-curlrc'; then
    echodebug "explicit -curlrc"
    if [ -f "$curlrc" ]; then
      curl_token_src=curlrc
    else
      curl_token_src=curlrc_not_found
    fi
  fi

  # token at the command line takes second highest precedence
  if [ -z "$curl_token_src" ] && [ -n "$token" ] &&
     echo "$TFH_CMDLINE" | grep -qE -- '-token'; then
    echodebug "explicit -token"
    curl_token_src=token
  fi

  # curlrc from any source (default included) comes third
  if [ -z "$curl_token_src" ] && [ -f "$curlrc" ]; then
    echodebug "curlrc from env and config file"
    curl_token_src=curlrc
  fi

  # token from the config file or environment var comes last
  if [ -z "$curl_token_src" ] && [ -n "$token" ]; then
    echodebug "token from env and config file"
    curl_token_src=token
  fi

  if [ -z "$curl_token_src" ]; then
    curl_token_src=none
  fi

  if [ -z "$token" ]; then
    token_status="empty"
  else
    token_status="not empty"
  fi

  case $curl_token_src in
    curlrc)
      echov "token:     $token_status, unused"
      echov "curlrc:    $curlrc"
      ;;
    token)
      echov "token:     $token_status"
      echov "curlrc:    $curlrc, unused"
      ;;
    curlrc_not_found)
      echov "token:     $token_status, unused"
      echov "curlrc:    $curlrc specified but not found"
      ;;
    none)
      echov "token:     empty"
      echov "curlrc:    $curlrc not found"
      ;;
  esac

  return 9
}

