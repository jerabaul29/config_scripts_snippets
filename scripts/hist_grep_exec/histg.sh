#!/bin/bash

function hg() {
    if [ $# -eq 0 ]; then
        echo "No arguments provided; -h for help"
        return 1
    fi

    if [ "$1" == "-h" ]; then
      echo "A bash script to find patterns in history, avoiding duplicates (also non consecutive)"
      echo "use: histg [grep patter]"
      echo "ex : histg S.I"
      return 0
    fi
    
    if [[ "$1" == "-v" ]]; then
        echo "v2.0"
        return 0
    fi

    # local -r HISTSIZE=100000              # put it if not defined in the ~/.bashrc
    local -r HISTFILE="${HOME}/.bash_history"     # CONFIG: Or wherever you bash history file lives
    set -o history               # enable history

    local -r PATH_TO_SAVELAST="${HOME}/.last_hg_output"

    # the first filtering: grep with the first patter, sort by command, tak away duplicates, sort by number
    local OUTPUT
    OUTPUT="$(history | grep -i "$1" | sort -k2 | tac | uniq -f 1 | sort -n)"

    # remove all commands that are hg and hx
    OUTPUT="$(echo "${OUTPUT}" | grep -v " hg " | grep -v " hx " | awk '{$1=$1;print}')"
    # remove the history line numbers
    OUTPUT="$(echo "${OUTPUT}" | cut -f2- --delimiter=" ")"

    # PERF: can do all the grepping only once, and remove color from the one to write (using sed ?)
    # at this point, already no duplicates, and ordered: just need to apply more grep
    local COLORED=${OUTPUT}
    while [ "$1" ]
    do
      COLORED="$(echo "${COLORED}" | grep -i --color=always "$1")"
      OUTPUT="$(echo "${OUTPUT}" | grep -i "$1")"
      shift
    done

    # the output to the console
    OUTPUT="$(echo "${OUTPUT}" | awk '{printf("% 4d  %s\n", NR, $0)}')"
    COLORED="$(echo "${COLORED}" | awk '{printf("% 4d  %s\n", NR, $0)}')"

    echo "${COLORED}"

    # saving to file for use with histx
    rm "${PATH_TO_SAVELAST}"
    touch "${PATH_TO_SAVELAST}"
    echo "${OUTPUT}" | cat > "${PATH_TO_SAVELAST}"
}

# TODO: shellcheck
