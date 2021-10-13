#!/bin/bash

# exit if a command fails; to circumvent, can add specifically on commands that can fail safely: " || true "
# set -o errexit
# make sure to show the error code of the first failing command
# set -o pipefail
# do not overwrite files too easily
# set -o noclobber
# exit if try to use undefined variable
# set -o nounset
# on globbing that has no match, return nothing, rather than return the dubious default ie the pattern itself
# shopt -s nullglob

# in order to be able to do the change of the parent terminal, must be a function not a script
function zx() {
    if [ $# -eq 0 ]; then
        echo "No arguments provided; -h for help"
        # TODO: check error number
        return 1
    fi 

    if [ "$1" == "-h" ]; then
        echo "Change path according to the result of zg"
        echo "use: zx number"
        echo "ex : zx 4"
        return 0
    fi
    
    if [ "$1" == "-h" ]; then
        echo "Change path according to the result of zg v"
        echo "use: zx number"
        echo "ex : zx 4"
        return 0
    fi
    
    if [ "$1" == "-v" ]; then
        echo "v2.0"
        return 0
    fi

    PATH_TO_SAVELAST="${HOME}/.last_zg_output"

    SELECTED_COMMAND="cd $(head -$1 ${PATH_TO_SAVELAST} | tail -1 | cut -c 7-)"
    echo "${SELECTED_COMMAND}"
    eval ${SELECTED_COMMAND}
    
    return 0
}

