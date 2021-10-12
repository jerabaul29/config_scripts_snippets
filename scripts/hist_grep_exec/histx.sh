#!/bin/bash

function hx() {
  if [ "$1" == "-h" ]; then
    echo "A bash script to execute the n-th command shown by histg"
    echo "use: histx number"
    echo "ex : histx 4"
    return
  fi

  # TODO: automate how to set the PATH_TO_SAVELAST and share it with histx
  PATH_TO_SAVELAST="/home/jrlab/Desktop/Git/MyBashScripts/Data/last_histg_output"

  SELECTED_COMMAND="$(head -$1 ${PATH_TO_SAVELAST} | tail -1 | tr -s ' ' | awk '{$1=$1;print}' | cut -d ' ' -f 2-)"
  echo "${SELECTED_COMMAND}"
  eval ${SELECTED_COMMAND}
}
