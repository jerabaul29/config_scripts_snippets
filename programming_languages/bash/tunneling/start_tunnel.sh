# pi@raspberrypi:~/Scripts $ cat start_tunnel.sh 

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

# parameters for the script
# information about the remote
REMOTE_NAME_OR_IP="jjrfnextbox.dedyn.io"
USER_ON_REMOTE="ssh_forwarding_user_s22a"
SSH_PORT_ON_REMOTE="31483"
FORWARDED_PORT_ON_REMOTE="8080"

# information 
FORWARDED_PORT_ON_LOCAL="22"

echo "sleep..."
sleep 30

echo "start ssh agent and add identity"
eval `ssh-agent`
ssh-add ~/.ssh/id_rsa__nextbox__ssh_forwarding_user_s22a

echo "start autossh tunneling"
autossh -v -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -NR "${FORWARDED_PORT_ON_REMOTE}":localhost:"${FORWARDED_PORT_ON_LOCAL}" "${USER_ON_REMOTE}"@"${REMOTE_NAME_OR_IP}" -p "${SSH_PORT_ON_REMOTE}"

echo "something bad happened; autossh returned; this should not happen"
