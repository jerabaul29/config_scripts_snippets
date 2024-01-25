# exit if a command fails; to circumvent, can add specifically on commands that can fail safely: " || true "
set -o errexit
# make sure to show the error code of the first failing command
set -o pipefail
# do not overwrite files too easily
# to override the noclobber: >| instead of > only
set -o noclobber
# exit if try to use undefined variable
set -o nounset

# on globbing that has no match, return nothing, rather than return the dubious default ie the pattern itself
# see " help shopt "; use the -u flag to unset (while -s is set)
shopt -s nullglob

###############################

if [ $# -eq 0 ]; then
    # all good
    :
elif [ $# -eq 1 ]; then
    if [ "$1" == "-h" ]; then
      echo "Usage:"
      exit 0
    fi
    # all good
    :
else
    echo "Wrong number of arguments, abort; see help with -h"
    exit 1
fi

# check that the tmux session name is free
if [ $# -eq 1 ]; then
  found_session=$(tmux ls 2> /dev/null | grep -c "$1" || true)

  if [ "$found_session" != 0 ]; then
    echo "Collision in session name!"
    echo "running:    tmux ls | grep $1"
    echo "returned    $(tmux ls | grep "$1")"
    echo "choose a different session name!"
    exit 1
  fi

  tmux new -s "$1" -d
else
  tmux new -d
fi

tmux split-window -h
tmux send-keys -t 2 'eval "$(/home/jrmet/miniconda3/bin/conda shell.bash hook)" && conda activate myenv' C-m
tmux send-keys -t 2 "ipython3" C-m
tmux send-keys -t 1 "hlx" C-m
tmux select-pane -t 1

tmux attach

