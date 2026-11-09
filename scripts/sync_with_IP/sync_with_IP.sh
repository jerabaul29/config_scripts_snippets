#!/bin/bash

###############################

# Sync Git working-tree files to/from ~/Desktop/Git/<repo-name>/ on a remote.
# Git metadata is excluded; destination-only files are never deleted.
# The remote username defaults to the current local username.
# how to install: source in your .bashrc or similar; for example in mine:
#     source /home/jeanr/Desktop/Git/config_scripts_snippets/scripts/sync_with_IP/sync_with_IP.sh
# Run from anywhere inside the repository:
#     source ~/.config/ki_utvikling_ip.dat && grf "$VM_KI_IP"
#     grt "$VM_KI_IP" remote_user --exclude '*.nc' --exclude '*.csv'
# Quote exclude patterns to prevent local shell expansion.

###############################

# helper functions

function get_crrt_git_root () {
    git rev-parse --show-toplevel
}

function get_git_repo_name () {
    local git_repo_root
    git_repo_root=$(get_crrt_git_root) || return 1
    printf '%s\n' "${git_repo_root##*/}"
}

function _git_rsync() {
    local direction="$1"
    shift
    local command_name="grt"
    if [[ "$direction" == "from" ]]; then
        command_name="grf"
    fi

    local -a positional=() excludes=(--exclude '.git')
    while (( $# )); do
        case "$1" in
            -h|--help)
                printf 'Usage: %s HOST [USER] [--exclude PATTERN ...]\n' "$command_name"
                printf '%s\n' \
                    "Sync working-tree files $direction ~/Desktop/Git/<repo-name>/ on HOST." \
                    "USER defaults to the current local username." \
                    "Options may appear before or after HOST and USER." \
                    "Repeat --exclude as needed; quote patterns: --exclude '*.nc' --exclude '*.csv'" \
                    "Git metadata is excluded; destination-only files are not deleted." \
                    "Existing destination files may be overwritten without prompting." \
                    "The remote parent directory is created when syncing to it." \
                    "Requires SSH access and rsync with --protect-args support on both machines." \
                    "-h, --help: show help; -v, --version: show version."
                return 0
                ;;
            -v|--version)
                printf '%s\n' "v1.1"
                return 0
                ;;
            --exclude)
                if (( $# < 2 )) || [[ -z "$2" ]]; then
                    printf '%s\n' "Error: --exclude requires a non-empty pattern." >&2
                    return 1
                fi
                excludes+=(--exclude "$2")
                shift 2
                ;;
            --exclude=*)
                if [[ -z "${1#--exclude=}" ]]; then
                    printf '%s\n' "Error: --exclude requires a non-empty pattern." >&2
                    return 1
                fi
                excludes+=(--exclude "${1#--exclude=}")
                shift
                ;;
            --)
                shift
                positional+=("$@")
                break
                ;;
            -*)
                printf 'Error: unknown option: %s\n' "$1" >&2
                return 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if (( ${#positional[@]} < 1 || ${#positional[@]} > 2 )); then
        printf 'Usage: %s HOST [USER] [--exclude PATTERN ...]; -h for help\n' "$command_name" >&2
        return 1
    fi

    local remote_host="${positional[0]}" remote_user
    if (( ${#positional[@]} == 2 )); then
        remote_user="${positional[1]}"
    else
        remote_user=$(id -un) || return 1
    fi
    if [[ -z "$remote_host" || -z "$remote_user" ]]; then
        printf '%s\n' "Error: HOST and USER must not be empty." >&2
        return 1
    fi

    local git_repo_root
    if ! git_repo_root=$(get_crrt_git_root 2>/dev/null); then
        printf '%s\n' "Fatal: Not inside a Git working tree. Aborting." >&2
        return 1
    fi

    local remote="$remote_user@$remote_host"
    # A relative rsync remote path is resolved from the remote user's home.
    local remote_target="$remote:Desktop/Git/${git_repo_root##*/}/"
    if [[ "$direction" == "to" ]]; then
        ssh -- "$remote" 'mkdir -p "$HOME/Desktop/Git"' || return
        rsync -azv --protect-args "${excludes[@]}" -- "$git_repo_root/" "$remote_target"
    else
        rsync -azv --protect-args "${excludes[@]}" -- "$remote_target" "$git_repo_root/"
    fi
}

# git rsync to
function grt() {
    _git_rsync to "$@"
}

# git rsync from
function grf() {
    _git_rsync from "$@"
}
