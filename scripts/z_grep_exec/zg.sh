#!/bin/bash

# grep the output of the z data with the words given as input
function zg(){

    if [[ $# -eq 0 ]]; then
        echo "No arguments provided; -h for help"
        # TODO: check error number
        return 1
    fi

    if [[ "$1" == "-h" ]]; then
      echo "A bash script to find patterns in z database"
      echo "use: zg [grep patter]"
      echo "ex : zg git bash"
      return 0
    fi
    
    if [[ "$1" == "-h" ]]; then
      echo "A bash script to find patterns in z database"
      echo "use: zg [grep patter]"
      echo "ex : zg git bash"
      return 0
    fi

    if [[ "$1" == "-v" ]]; then
        echo "v2.0"
        return 0
    fi

    local -r PATH_Z_DATABASE="${HOME}/.z"
    local -r PATH_TO_SAVELAST="${HOME}/.last_zg_output"

    # read
    local OUTPUT="$(cat ${PATH_Z_DATABASE} | cut -f 1 -d "|")"

    # do the grepping
    local COLORED="${OUTPUT}"
    while [ "$1" ]
    do
      COLORED="$(echo "${COLORED}" | grep -i --color=always "$1")"
      OUTPUT="$(echo "${OUTPUT}" | grep -i "$1")"
      shift
    done

    local OUTPUT="$(echo "${OUTPUT}" | awk '{printf("% 4d  %s\n", NR, $0)}')"
    local COLORED="$(echo "${COLORED}" | awk '{printf("% 4d  %s\n", NR, $0)}')"

    echo "${COLORED}"

    # saving to file for use with zx; depending on the params used
    rm "${PATH_TO_SAVELAST}"
    echo "${OUTPUT}" > "${PATH_TO_SAVELAST}"
    
    return 0
    
}

