# set up a dummy web server serving a tmp folder on some arbitrary port
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"
echo "hello, from working in $WORK_DIR" >> index.txt
PORT_EXPOSED="8093"
LOCALHOST="127.0.0.1"
python3 -m http.server "$PORT_EXPOSED" --bind "$LOCALHOST" &
PID_SERVER="$!"
echo "python3 http.server running under PID $PID_SERVER"
echo "use it to kill the server when done with it"

# sleep a bit to let the time for the server to come up
sleep 1

# check that the server works:
curl "$LOCALHOST":8093/index.txt
