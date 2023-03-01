#!/bin/bash

function jpr() {
    if [[ $# == 0 ]]; then
        echo "No arguments provided; -h for help"
        return 1
    fi

    if [[ "$1" == "-h" ]]; then
      echo "A bash script to:"
      echo "  - convert .ipynb jupyter notebook to .py python script"
      echo "  - run the .py"
      echo "use: jpr [ipynb notebook]"
      echo "ex : jpr some_notebook.ipynb"
      return 0
    fi

    if [[ "$1" == "-v" ]]; then
        echo "v1.0"
        return 0
    fi

    filename=$(basename -- "$1")
    extension="${filename##*.}"
    filename="${filename%.*}"

    if [[ ! -f "$filename.$extension" ]]; then
        echo "non existent file; cannot find: $filename.$extension"
        return 2
    fi

    if [[ "$extension" != "ipynb" ]]; then
        echo "wrong extension; expected .ipynb, got .${extension}"
        return 3
    fi

    jupyter nbconvert --to script "$filename.$extension"
    python3 "$filename.py"
    rm "$filename.py"
}
