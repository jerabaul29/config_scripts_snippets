# to work, this will require having a mamba environment set up
# !!!if you do not want to use the paid Anaconda Inc channels, MAKE SURE THAT YOU ONLY USE THE conda-forge CHANNEL!!!
# check with:
#     mamba config list

# I recommend to install as:
# cd ~/Desktop/Git
# git clone https://github.com/jerabaul29/config_scripts_snippets.git

# I recommend to make available as the hj command by adding to your ~/.bashrc:
# alias ct="~/Desktop/Git/config_scripts_snippets/scripts/tmux_and_ai_cli/tmux_and_ai_cli.sh"

###############################

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

# tmux session name is from the base name of the current location
SESSION_NAME=$(basename "$(pwd)")

# check that no tmux session name collision
found_session=$(tmux ls 2> /dev/null | grep -c "$SESSION_NAME" || true)

if [ "$found_session" != 0 ]; then
  echo "Collision in session name!"
  echo "running:    tmux ls | grep $SESSION_NAME"
  echo "returned    $(tmux ls | grep "$SESSION_NAME")"
  echo "choose a different session name!"
  exit 1
fi

tmux new -s "$SESSION_NAME" -d

# split and send commands to establish:
tmux split-window -h
tmux split-window -v

# NOTE: adapt the path / mamba env name if necessary
# NOTE: the following pane numbers are for tmux set up with https://github.com/gpakosz/.tmux.git , i.e. tmux pane numbering starting at 1
# for 0-indexed tmux panes (that is usually the default), reduce the indexes below by 1, i.e. 1->0 2->1 etc
tmux send-keys -t 2 'eval "mamba activate dev"' C-m
tmux send-keys -t 1 'eval "mamba activate dev"' C-m
tmux send-keys -t 3 'eval "mamba activate dev"' C-m

# left: copilot cli in the current folder
tmux send-keys -t 2 "copilot --allow-all-tools"

# right top: hlx in the current folder
tmux send-keys -t 1 "hlx" C-m

# right bottom: just a terminal in the current folder

# we still need to attach to the session
tmux attach
