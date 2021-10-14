#!/bin/bash

function hx() {
  if [ "$1" == "-h" ]; then
    echo "A bash script to execute the n-th command shown by histg"
    echo "use: histx number"
    echo "ex : histx 4"
    return
  fi
  
  if [[ "$1" == "-v" ]]; then
        echo "v2.0"
        return 0
  fi

  local -r PATH_TO_SAVELAST="${HOME}/.last_hg_output"

  local -r SELECTED_COMMAND="$(head "-$1" "${PATH_TO_SAVELAST}" | tail -1 | tr -s ' ' | awk '{$1=$1;print}' | cut -d ' ' -f 2-)"
  echo "${SELECTED_COMMAND}"
  eval "${SELECTED_COMMAND}"
}

