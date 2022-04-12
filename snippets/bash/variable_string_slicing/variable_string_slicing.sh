# a small example of how to slice variables and strings in bash

##############################################
# icecream in bash; can either source the repo at https://github.com/jtplaarj/IceCream-Bash after cloning it locally, or just include in any source

# print file, function name, line, variable and its value
ic () {
    local tmp="${1}[@]"
    echo "(${BASH_SOURCE[1]},${FUNCNAME[1]}) ${BASH_LINENO[0]}: $1 - ${!tmp}"
}

# print file, function name, line, and message string
icp () {
    echo "(${BASH_SOURCE[1]},${FUNCNAME[1]}) ${BASH_LINENO[0]}: $1"
}

# print full call tree and variable and its value
ict () {
    local tmp="${1}[@]"
    for((i=${#BASH_SOURCE[@]}-2;i>=0;i--));
    do
        echo -n "(${BASH_SOURCE[$i+1]},${FUNCNAME[$i+1]}) ${BASH_LINENO[$i]}: "
    done
    echo "$1 - ${!tmp}"
}

# print full call tree and message string
ictp () {
    for((i=${#BASH_SOURCE[@]}-2;i>=0;i--));
    do
        echo -n "(${BASH_SOURCE[$i+1]},${FUNCNAME[$i+1]}) ${BASH_LINENO[$i]}: "
    done
    echo "$1"
}

##############################################

SOME_VAR="123456789"

# skip 4 chars, and keep the 2 first that remain
SOME_SLICE="${SOME_VAR:4:2}"

ic SOME_SLICE

