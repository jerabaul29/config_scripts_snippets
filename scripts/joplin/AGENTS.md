# Script for good practice run of Joplin AppImage

This should describe how to design a small bash script compatible with modern Ubuntu distros. The script should be in this folder, self contained, and named: `joplin_run.sh` .

The goal of the script is to make it easier to use Joplin in a safe way: making sure it is updated, and running well isolated with minimum sets of rights with bubblewrap.

Assumptions about the system setup:
- There is one or more Joplin AppImage and associated sha512 files under `$HOME/Desktop/Software/Joplin` ; only the latest and most up to date should be run.
- The appimage can be run and the necessary packages are on the system so it runs without error - this is the user's responsibility.
- The bubblewrap (`bwrap`) program is installed - this is the user's responsibility.

Rules for the bash script:
- Use a preamble that makes bash as safe as possible.
- Make sure the script is always safe to run.
- Code defensively: make sure that any failed assumption or failed command makes the script abort and print an error message + return an error code.
- Check all assumptions actively.

Tasks that the bash script should implement and run in sequence (any failure should abort with error message and error code):
- Find the latest local version of the appimage in `$HOME/Desktop/Software/Joplin` and print it for the user.
- Check that the sha512 for the latest local version (.sha512 corresponding file) is correct according to `sha512sum -c` and print it for the user.
- Get the latest version available by `wget https://github.com/laurent22/joplin/releases/latest` .
- Use a regexp with field capture to find the latest version released: it should be the first match for a string in the wget output looking like https://github.com/laurent22/joplin/releases/tag/v3.7.21 (note version is v. some number . some number . some number), and print the corresponding version for the user.
- Check that the appimage version is equal to the latest github release version, and print confirmation to the user.
- Start the appimage (for now without bubblewrap).
