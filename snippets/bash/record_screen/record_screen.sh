# example of snippet to record screen and then convert to a more easy format

# perform the recording itself
# record screen: ctrl alt maj r to start and stop
# it is also possible to use the "PrintScreen" key and use the video recording option on modern ubuntu

# convert from webm format to gif or other format; example of commands
sInput='Screencast from 24. juni 2021 kl. 13.43 +0200.webm' 
sOutput="$(basename "${sInput%.*}")";
ffmpeg -i "${sInput}" -pix_fmt rgb8 "${sOutput}.gif" && gifsicle --optimize=3 --output "${sOutput}-optimized.gif" --resize-height 600 "${sOutput}.gif"
