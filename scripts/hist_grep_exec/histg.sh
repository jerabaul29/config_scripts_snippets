#!/bin/bash

if [ $# -eq 0 ]; then
    echo "No arguments provided; -h for help"
    exit 1
fi

if [ "$1" == "-h" ]; then
  echo "A bash script to find patterns in history, avoiding duplicates (also non consecutive)"
  echo "use: histg [grep patter]"
  echo "ex : histg S.I"
  exit 0
fi

# TODO: automate how to recover HISTSIZE and share it with bash_rc
HISTSIZE=100000              # need this, because does not read .bashrc so does not know how big a HISTSIZE
HISTFILE="~/.bash_history"   # Or wherever you bash history file lives
set -o history               # enable history

# TODO: automate how to set the PATH_TO_SAVELAST and share it with histx
PATH_TO_SAVELAST="/home/jrlab/Desktop/Git/MyBashScripts/Data/last_histg_output"

# the first filtering: grep with the first patter, sort by command, tak away duplicates, sort by number
OUTPUT="$(history | grep -i "$1" | sort -k2 | tac | uniq -f 1 | sort -n)"

# remove all commands that are hg and hx
OUTPUT="$(echo "${OUTPUT}" | grep -v " hg " | grep -v " hx " | awk '{$1=$1;print}')"
# remove the history line numbers
OUTPUT="$(echo "${OUTPUT}" | cut -f2- --delimiter=" ")"
# echo "${OUTPUT}"

# TODO: do all the grepping only once, and remove color from the one to write (using sed ?)
# at this point, already no duplicates, and ordered: just need to apply more grep
COLORED=${OUTPUT}
while [ "$1" ]
do
  COLORED="$(echo "${COLORED}" | grep -i --color=always "$1")"
  OUTPUT="$(echo "${OUTPUT}" | grep -i "$1")"
  shift
done

# the output to the console
# TODO: instead of using numbers for the calls to hx, option to use letters
#       so that no need to lift fingers to letter keys
OUTPUT="$(echo "${OUTPUT}" | awk '{printf("% 4d  %s\n", NR, $0)}')"
COLORED="$(echo "${COLORED}" | awk '{printf("% 4d  %s\n", NR, $0)}')"

echo "${COLORED}"
# echo "${OUTPUT}"

# saving to file for use with histx
> ${PATH_TO_SAVELAST}
echo "${OUTPUT}" | cat >> ${PATH_TO_SAVELAST}
