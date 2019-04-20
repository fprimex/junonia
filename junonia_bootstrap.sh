# This function can be copied to the top level script to set absolute paths to
# the script. From there, junonia.sh, other shell libraries, and other assets
# can be loaded or referenced. For example, for a project with directories like
# the following:

# /home/user/foo/code/project.git/script
# /home/user/foo/code/project.git/lib/junonia.sh

# the following code could be used in script:
#
# # copied from below
# junonia_bootstrap () {
# ...
# }
#
# junonia_bootstrap
# . "$JUNONIA_PATH/lib/junonia.sh"
# # continue using junonia functions like junonia_run, echoerr, etc...

# Determine the script location. Note that this is not POSIX but portable to
# many systems with nearly any kind of implementation of readlink. With the
# exception of the function name this is generic and does not rely on anything
# specific to the rest of junonia.
junonia_bootstrap () {
  # Get the command used to start this script
  JUNONIA_TARGET="$0"

  # If executing via a series of symlinks, resolve them all the way back to the
  # script itself. Some danger here of infinitely cycling.
  while [ -h "$JUNONIA_TARGET" ]; do
    # look at what this link points to
    link="$(file -h "$JUNONIA_TARGET" | sed 's/^.*symbolic link to //')"
    if [ "$(echo "$link" | cut -c -1)" = "/" ]; then
      # Link path is absolute; just need to follow it.
      JUNONIA_TARGET="$link"
    else
      # Link path is relative, need to relatively follow it.
      JUNONIA_TARGET="${JUNONIA_TARGET%/*}"
      JUNONIA_TARGET="$JUNONIA_TARGET/$link"
    fi
  done

  # Now target should be like the following, where 'script' is not a symlink:
  # /some/path/to/the/actual/script
  # /home/user/code/project/name/bin/script
  readonly JUNONIA_TARGET
  readonly JUNONIA_PATH="$(cd "$(dirname "$JUNONIA_TARGET")" && pwd -P)"
}
