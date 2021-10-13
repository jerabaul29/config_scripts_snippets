#!/bin/bash

# in order to be able to do the change of the parent terminal, must be a function not a script
# move to the entry number n coming out of the zh command
function zx() {

    if [[ $# -eq 0 ]]; then
        echo "No arguments provided; -h for help"
        # TODO: check error number
        return 1
    fi 

    if [[ "$1" == "-h" ]]; then
        echo "Change path according to the result of zg"
        echo "use: zx number"
        echo "ex : zx 4 will move to the entry 4 of the last zg output"
        return 0
    fi
    
    if [[ "$1" == "-v" ]]; then
        echo "v2.0"
        return 0
    fi

    local -r PATH_TO_SAVELAST="${HOME}/.last_zg_output"

    local -r SELECTED_COMMAND="cd $(head -$1 ${PATH_TO_SAVELAST} | tail -1 | cut -c 7-)"
    echo "${SELECTED_COMMAND}"
    eval ${SELECTED_COMMAND}
    
    return 0
}

