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

# create an empty file
EMAIL_FILENAME="email_content.txt"
>| "${EMAIL_FILENAME}"

echo "Subject: H22 backup RPi4 boot" >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"
echo "IP $(curl ifconfig.me)" >> "${EMAIL_FILENAME}"
echo "Automatic message from the H22 backup RPi4 after boot." >> "${EMAIL_FILENAME}"
echo "Connect to me to start and set up the backup!" >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"
echo "From nextbox S22 RPi:" >> "${EMAIL_FILENAME}"
echo "eval \"\$(ssh-agent -s)\"" >> "${EMAIL_FILENAME}"
echo "ssh-add .ssh/id_rsa_nextbox_s22" >> "${EMAIL_FILENAME}"
echo "ssh pi@localhost -p 8080 -o PreferredAuthentications=publickey" >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"
date >> "${EMAIL_FILENAME}"
echo "" >> "${EMAIL_FILENAME}"
df -h >> "${EMAIL_FILENAME}"
