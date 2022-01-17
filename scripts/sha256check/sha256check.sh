##############################################

# a function to perform sha256 integrity check
# this is just a small wrapper around sha256sum,
# with an (arguably) simpler interface.
function sha256check
{
    if [[ "$1" == "-h" ]]; then
        echo "A bash function to check sha256 integrity of a single file."
        echo "use: sha256check PATH_TO_FILE EXPECTED_SHA256"
        echo "ex: sha256check besseggen.jpg 3a48c6e5bfcf1f3d50d908bdbcd776555dbab437d65b39673bfffa70af07da02"
        return 0
    fi

    if [[ "$1" == "-v" ]]; then
        echo "v1.0"
        return 0
    fi

    if [[ "$#" != 2 ]]; then
        echo "expect 2 arguments: i) path to single file, ii) expected sha256"
        echo "but got $# arguments!"
        echo "abort!"
        return 5
    fi

    if [[ ! -f "$1" ]]; then
        echo "first argument should be a file"
        echo "got $1 , which does not exists as a file"
        return 5
    fi

    local -r SHA_RESULT=$(echo "$2 $1" | sha256sum --check)
    echo "$SHA_RESULT"
    return 0
}
