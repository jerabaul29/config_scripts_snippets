# in bash, it is possible to use variables with defaults. This is just an illustration of this:

source "${HOME}/Desktop/Git/IceCream-Bash/src/ic.sh"

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
# if VARIABLE_4 is not set, print error message; this also aborts the program

echo "We never reach this point!!"

