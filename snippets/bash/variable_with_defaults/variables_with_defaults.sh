# in bash, it is possible to use variables with defaults. This is just an illustration of this:

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

FOO_1="${VARIABLE_1:-default_1}"  # If variable not set or null, use default.
# If VARIABLE was unset or null, it still is after this (no assignment done).

ic FOO_1
ic VARIABLE_1

FOO_2="${VARIABLE_2:=default_2}"  # If variable not set or null, set it to default.
# If VARIABLE was unset or null, it is set after this (assignment done).

ic FOO_2
ic VARIABLE_2

SET_3="set_3"
FOO_3="${SET_3:-default_3}"

ic FOO_3
ic SET_3

FOO_4=${VARIABLE_4:+default_4}

ic FOO_4
ic VARIABLE_4

SET_5="set_5"
FOO_5=${SET_5:+default_5}

ic FOO_5
ic SET_5

FOO_6="${VARIABLE_6:?default_6}"
# if VARIABLE_6 is not set, print error message; this also aborts the program

echo "We never reach this point!!"

