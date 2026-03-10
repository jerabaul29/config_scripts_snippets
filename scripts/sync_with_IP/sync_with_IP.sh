#!/bin/bash

###############################

# goal: sync a GH repository with its state on a target IP machine; either sync to or from, using rsync
# assumption: the GH repositories are always hosted in $HOME/Desktop/Git/
# the username is the same on the remote as on the local machine
# how this works: determine the root path of the repository and its name, determine the path on the remote, and sync
# how to install: source in your .bashrc or similar

###############################

# helper functions

function get_crrt_git_root () {
  GIT_REPO_ROOT=$(git rev-parse --show-toplevel)
  echo "$GIT_REPO_ROOT"
}

function get_git_repo_name () {
  GIT_BASE_NAME=$(basename "$(git rev-parse --show-toplevel)")
  echo "$GIT_BASE_NAME"
}

###############################

# git rsync to
function grt() {
    if [ $# -eq 0 ]; then
        echo "No arguments provided; -h for help"
        return 1
    fi

    if [ "$1" == "-h" ]; then
      echo "git rsync to"
      echo "provide a single argument: the IP of the machine to which rsync the current git repo"
      return 0
    fi
    
    if [[ "$1" == "-v" ]]; then
        echo "v1.0"
        return 0
    fi

  REMOTE_IP="$1"

  local REMOTE_TARGET="$HOME/Desktop/Git/"

  local GIT_REPO_ROOT="$(get_crrt_git_root)"

  rsync -avzP "$GIT_REPO_ROOT" "$USER@$REMOTE_IP:$REMOTE_TARGET"
}

###############################

# git rsync from
function grf() {
    if [ $# -eq 0 ]; then
        echo "No arguments provided; -h for help"
        return 1
    fi

    if [ "$1" == "-h" ]; then
      echo "git rsync from"
      echo "provide a single argument: the IP of the machine from which rsync the current git repo"
      return 0
    fi
    
    if [[ "$1" == "-v" ]]; then
        echo "v1.0"
        return 0
    fi

  REMOTE_IP="$1"

  local GIT_BASE_NAME="$(get_git_repo_name)"
  local REMOTE_TARGET="$HOME/Desktop/Git/$GIT_BASE_NAME"

  local GIT_REPO_ROOT="$(get_crrt_git_root)"
  local GIT_REPO_LOCATION=$(dirname "$GIT_REPO_ROOT")

  rsync -avzP "$USER@$REMOTE_IP:$REMOTE_TARGET" "$GIT_REPO_LOCATION"
}
