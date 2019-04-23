# This is a compact version of junonia_bootstrap for easy copyhing into user
# scripts. For a fully commented, documented version of this script see
# https://github.com/fprimex/junonia/blob/master/junonia.sh
junonia_bootstrap () {
  JUNONIA_TARGET="$0"
  while [ -h "$JUNONIA_TARGET" ]; do
    JUNONIA_PATH="$(file -h "$JUNONIA_TARGET" | \
                    sed 's/^.*symbolic link to //')"
    if [ "$(echo "$JUNONIA_PATH" | cut -c -1)" = "/" ]; then
      JUNONIA_TARGET="$JUNONIA_PATH"
    else
      JUNONIA_TARGET="$(dirname $JUNONIA_TARGET)"
      JUNONIA_TARGET="$JUNONIA_TARGET/$JUNONIA_PATH"
    fi
  done
  readonly JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
  readonly JUNONIA_TARGET="$JUNONIA_PATH/$(basename $JUNONIA_TARGET)"
}
