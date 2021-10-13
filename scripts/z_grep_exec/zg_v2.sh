#!/bin/bash

# exit if a command fails; to circumvent, can add specifically on commands that can fail safely: " || true "
set -o errexit
# make sure to show the error code of the first failing command
set -o pipefail
# do not overwrite files too easily
set -o noclobber
# exit if try to use undefined variable
set -o nounset
# on globbing that has no match, return nothing, rather than return the dubious default ie the pattern itself
shopt -s nullglob

function zg(){

    if [ $# -eq 0 ]; then
        echo "No arguments provided; -h for help"
        exit 1
    fi

    if [ "$1" == "-h" ]; then
      echo "A bash script to find patterns in z database"
      echo "use: zg [grep patter]"
      echo "ex : zg git bash"
      exit 0
    fi
    
    if [ "$1" == "-h" ]; then
      echo "A bash script to find patterns in z database"
      echo "use: zg [grep patter]"
      echo "ex : zg git bash"
      exit 0
    fi

    # instead, just read the z database
    PATH_Z_DATABASE="${HOME}/.z"

    PATH_TO_SAVELAST="${HOME}/.last_zg_output"

    # read
    OUTPUT="$(cat ${PATH_Z_DATABASE} | cut -f 1 -d "|")"

    # do the grepping
    COLORED=${OUTPUT}
    while [ "$1" ]
    do
      COLORED="$(echo "${COLORED}" | grep -i --color=always "$1")"
      OUTPUT="$(echo "${OUTPUT}" | grep -i "$1")"
      shift
    done

    OUTPUT="$(echo "${OUTPUT}" | awk '{printf("% 4d  %s\n", NR, $0)}')"
    COLORED="$(echo "${COLORED}" | awk '{printf("% 4d  %s\n", NR, $0)}')"

    echo "${COLORED}"

    # saving to file for use with zx
    echo "${OUTPUT}" |> ${PATH_TO_SAVELAST}
    
    exit 0
    
}

