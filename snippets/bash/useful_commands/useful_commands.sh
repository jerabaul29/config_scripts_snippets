# some useful commands that I use often
# nice to have in bash history to be able to search!

# activate conda and a specific env
eval "$(~/miniconda3/bin/conda shell.bash hook)" && conda activate myenv

# unlock passwords and ssh; once the passphrase is loaded, just ctrl-shift-v to use it at the second step
pass show -c PATH/passphrase_PPI_ssh_key && ssh-add .ssh/id_ed25519_SOMEKEY && ssh USER@SERVER -v -X
