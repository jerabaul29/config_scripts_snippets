# exit if a command fails; to circumvent, can add specifically on commands that can fail safely: " || true "
set -o errexit
# make sure to show the error code of the first failing command
set -o pipefail
# do not overwrite files too easily
set -o noclobber
# exit if try to use undefined variable
set -o nounset
# on globbing that has no match, return nothing, rather than return the dubious default ie the pattern itself
# see " help shopt "; use the -u flag to unset (while -s is set)
shopt -s nullglob

echo "wait for network"

while ! ping -c 1 -W 1 8.8.8.8; do
    echo "Waiting for 8.8.8.8 - network interface might be down or network not available..."
    sleep 300
done
