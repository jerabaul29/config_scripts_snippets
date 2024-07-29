# to work, this will require having a miniconda environment set up (with miniconda root in your home)
# with env name myenv ; this is so that all repl / lsps / packages etc are available

# I recommend to install as:
# cd ~/Desktop/Git
# git clone https://github.com/jerabaul29/config_scripts_snippets.git

# I recommend to make available as the hj command by adding to your ~/.bashrc:
# alias hj="~/Desktop/Git/config_scripts_snippets/scripts/helix_and_repl/helix_and_repl.sh"

# for this to work best, I recommend that you use macros to be able to send code to jupyter: see e.g.:
# https://github.com/jerabaul29/config_scripts_snippets/blob/4d1202e28ed028535e83956f2d5f12bc92110ff4/configs/helix/config.toml#L32-L33
# and the discussion at: https://github.com/helix-editor/helix/issues/2806 .

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

USE_FILE=false

if [ $# -eq 0 ]; then
    # all good
    :
elif [ $# -eq 1 ]; then
    if [ "$1" == "-h" ]; then
      echo "Usage:"
      echo "  * hj          : open a repl compatible tmux + helix env in the current folder"
      echo "  * hj FILENAME : open a repl compatible tmux + helix env in the current folder, opening FILENAME in helix"
      echo "  * hj -h       : display this help"
      exit 0
    else
      if [ ! -f "$1" ]; then
        echo "File $1 not found!"
        exit 2
      fi
      USE_FILE=true
      FILENAME="$1"
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
tmux split-window -v
# NOTE: the following pane numbers are for tmux set up with https://github.com/gpakosz/.tmux.git , i.e. tmux pane numbering starting at 1
# for 0-indexed tmux panes (that is usually the default), reduce the indexes below by 1, i.e. 1->0 2->1 etc
tmux send-keys -t 2 'eval "$(~/miniconda3/bin/conda shell.bash hook)" && conda activate myenv' C-m
tmux send-keys -t 1 'eval "$(~/miniconda3/bin/conda shell.bash hook)" && conda activate myenv' C-m
tmux send-keys -t 3 'eval "$(~/miniconda3/bin/conda shell.bash hook)" && conda activate myenv' C-m
tmux send-keys -t 2 "ipython3" C-m
if [ $USE_FILE = true ]; then
  tmux send-keys -t 1 "hlx $FILENAME" C-m
else
  tmux send-keys -t 1 "hlx" C-m
fi
tmux select-pane -t 1

tmux attach
