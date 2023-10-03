#!/bin/bash

if [ $# -eq 0 ]; then
    echo "No arguments provided; -h for help"
    exit 1
fi

if [ "$1" == "-h" ]; then
  echo "A bash script to git add, commit and push"
  echo 'use: ga "message"'
  echo "ex : histg S.I"
  exit 0
fi

git add .
git commit -m "$1"
git push
