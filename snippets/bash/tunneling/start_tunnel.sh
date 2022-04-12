# to make this safely, remember to DISABLE LOCAL PORT FORWARDING FOR THE REMOTE SSH TUNNEL USER
# see post and explanations at: https://jerabaul29.github.io/jekyll/update/2022/03/12/Secure-reverse-ssh-tunnel.html

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

# we connect from the current host in a way similar to: ssh USER_ON_REMOTE@REMOTE_NAME_OR_IP -p SSH_PORT_ON_REMOTE
REMOTE_NAME_OR_IP="something.dedyn.io"
USER_ON_REMOTE="limited"
# the port to use to ssh to "main" from the internet;
# I set a forwarding rule from a randomly chosen
# public port to the "main" port 22, to keep cleaner logs...
SSH_PORT_ON_REMOTE="some_port_1"

# the remote port REMOTE_NAME_OR_IP:FORWARDED_PORT_ON_REMOTE will be forwarded to the local port localhost:FORWARDED_PORT_ON_LOCAL
FORWARDED_PORT_ON_REMOTE="some_port_2"
FORWARDED_PORT_ON_LOCAL="some_port_3"

echo "sleep..."
sleep 30

echo "wait for network"
while ! ping -c 1 -W 1 8.8.8.8; do
    echo "Waiting for 8.8.8.8 - network interface might be down or network not available..."
    sleep 300
done

echo "start ssh agent and add identity"
eval `ssh-agent`
ssh-add ~/.ssh/id_rsa_some_key

while true; do
    # actually, do not use autossh: it requires opening extra ports
    # for the double checks, and keeping track of these if several
    # tunnels, etc, is a pain...
    # autossh -v -o ServerAliveInterval=120 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -NR "${FORWARDED_PORT_ON_REMOTE}":localhost:"${FORWARDED_PORT_ON_LOCAL}" "${USER_ON_REMOTE}"@"${REMOTE_NAME_OR_IP}" -p "${SSH_PORT_ON_REMOTE}"
    # ssh with alive options is enough to keep things up,
    # together with a bit of sshd setup
    echo "start autossh tunneling"
    ssh -o ServerAliveInterval=120 -o ServerAliveCountMax=3 -NR "${FORWARDED_PORT_ON_REMOTE}":localhost:"${FORWARDED_PORT_ON_LOCAL}" "${USER_ON_REMOTE}"@"${REMOTE_NAME_OR_IP}" -p "${SSH_PORT_ON_REMOTE}"
    sleep 300
done

echo "something bad happened; ssh returned; this should not happen; try again!"

