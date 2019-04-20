junonia_bootstrap () {
  JUNONIA_TARGET="$0"
  while [ -h "$JUNONIA_TARGET" ]; do
    link="$(file -h "$JUNONIA_TARGET" | sed 's/^.*symbolic link to //')"
    if [ "$(echo "$link" | cut -c -1)" = "/" ]; then
      JUNONIA_TARGET="$link"
    else
      JUNONIA_TARGET="${JUNONIA_TARGET%/*}"
      JUNONIA_TARGET="$JUNONIA_TARGET/$link"
    fi
  done
  readonly JUNONIA_TARGET
  readonly JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
}
