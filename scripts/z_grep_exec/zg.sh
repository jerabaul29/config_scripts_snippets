#!/bin/bash

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

# TODO: get z to work: command not found error if trying to use z

# instead, just read the z database
# TODO: automatic find path to .z
PATH_Z_DATABASE="/home/jrlab/.z"

# TODO: automate how to set the PATH_TO_SAVELAST and share it with histx
PATH_TO_SAVELAST="/home/jrlab/Desktop/Git/MyBashScripts/Data/last_zg_output"

# read
OUTPUT="$(cat ${PATH_Z_DATABASE} | cut -f 1 -d "|")"
# echo "${OUTPUT}"

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
# echo "${OUTPUT}"

# saving to file for use with zx
> ${PATH_TO_SAVELAST}
echo "${OUTPUT}" | cat >> ${PATH_TO_SAVELAST}