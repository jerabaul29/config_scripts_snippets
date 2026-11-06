#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

# by now, we want to robustify this with bubblewrap:
# - no network whatsoever
# - read only, only the relevant locations: the location of helix, the location of helix config and language, the conda / mamba folders
# - if no argument provided, the cwd is read write - this is where we work
# - if a list of file is provided, the list of files is read write - this is where we work
# - also have a config array of paths to e.g. lsps, that can be maintained for example by the user, that is read only
# - everything else is off-borders
# - a compromised or malicious helix should not be able to read any sensitive file, even less write them, and should  not be able to exfiltrate anything
# - all lsps used should be local only anyways, so no loss of functionality
/home/jeanr/Desktop/Software/HelixEditor/helix-25.07.1-x86_64.AppImage

