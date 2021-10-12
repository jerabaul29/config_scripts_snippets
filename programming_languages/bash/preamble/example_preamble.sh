##############################################

# remember the guidelines! https://google.github.io/styleguide/shellguide.html

# for tests, use " [[ … ]] "
# for arithmetics, use " $(( … )) "
# when read only, remember to " declare -r SOME_VAR "
# I like better to use some_function(), _SOME_VAR conventions
# remember to check error codes: " $? "

# sounder programming environment

# exit if a command fails; to circumvent, can add specifically on commands that can fail safely: " || true "
set -o errexit
# make sure to show the error code of the first failing command
set -o pipefail
# do not overwrite files too easily
set -o noclobber
# exit if try to use undefined variable
set -o nounset
# on globbing that has no match, return nothing, rather than return the dubious default ie the pattern itself
shopt -s nullglob

# a few useful functions

# a function to write errors to the std err with timestamp; to use: " err "some error message" "
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# trap, i.e get signals and try to clean up

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

# local variables are visible to called functions, so local is quite weak, but still use local as much as possible

# PERFORM STATIC ANALYSIS on your scripts! https://github.com/koalaman/shellcheck

