# pi@raspberrypi:~/Scripts $ cat prepare_and_send_email.sh 

##############################################

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

##############################################

# start by waiting a bit - make sure network gets good time to get up etc
echo "sleep..."
sleep 30

##############################################

# parameters for the script
# path to the email file
EMAIL_FILENAME=XX

echo "wait for network"

while ! ping -c 1 -W 1 8.8.8.8; do
    echo "Waiting for 8.8.8.8 - network interface might be down or network not available..."
    sleep 300
done

echo "prepare the email content"

# create an empty file
>| "${EMAIL_FILENAME}"

echo "From: some_email@gmail.com" >> "${EMAIL_FILENAME}"
echo "To: some_email@gmail.com" >> "${EMAIL_FILENAME}"
echo "Subject: SOME_RPI backup RPi4 status" >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"

# custom information
echo "IP: $(curl ifconfig.me)" >> "${EMAIL_FILENAME}"
# information about the system
echo "current date: $(date)" >>  "${EMAIL_FILENAME}"
echo "uptime: $(uptime)" >>  "${EMAIL_FILENAME}"
echo "df -h output:" >> "${EMAIL_FILENAME}"
df -h >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"

# add any information to the body of the email
echo "SOME_INFORMATION" >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"

echo "send the email"

# sent the email
sendmail some_email@gmail.com < ${EMAIL_FILENAME}

echo "done"
