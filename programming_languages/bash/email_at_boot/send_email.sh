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

echo "prepare email..."
bash prepare_email.sh
echo "send email..."
sendmail -F "RPi Backup H22" -f "rpi_backup_h22" jean.rblt@gmail.com < email_content.txt
echo "done!"
