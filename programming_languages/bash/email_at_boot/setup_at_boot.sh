# to start:
# sudo crontab -e
# @reboot sleep 30; cd /home/pi/Scripts/; bash setup_at_boot.sh

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

# give time to start
echo "sleep for a few seconds to let the RPi start..."
sleep 10

echo "setup reverse ssh tunnel"
# set up the reverse ssh tunnel
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa__nextbox__ssh_forwarding_user_s22a
ssh -NR 8080:localhost:22 ssh_forwarding_user_s22a@URL -p PORT_TO_WHICH_SSH_ON_ROUTER -o PreferredAuthentications=publickey -v &

sleep 10
echo "prepare email"
# prepare the email
bash prepare_email.sh &

sleep 10
echo "send email"
# send the email
bash send_email.sh &

# give a bit of time to not clutter the terminal
sleep 60
