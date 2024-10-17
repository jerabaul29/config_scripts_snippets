- install bash-git-prompt: https://github.com/magicmonty/bash-git-prompt
- put the following in the .bashrc:

```bash
if [ -f "$HOME/.bash-git-prompt/gitprompt.sh" ]; then
	GIT_PROMPT_ONLY_IN_REPO=0
	GIT_PROMPT_THEME=Single_line_Dark # this one is nice
	source $HOME/.bash-git-prompt/gitprompt.sh
fi
```
