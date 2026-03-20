# General python coding practices

## About the project

TODO: describe the main aspects of the project

## Goal of this folder and code organization

TODO: explain how you want the project folder to be structured, what scripts and figures should be produced, etc

## Code practices

- have tests to run with pytest if relevant - for self implemented serious functions but not for small scripts
- have logging with loguru
- write simple, idiomatic python code
- use typing / type annotation for the functions
- use formal checkers for the code (install these in the mamba environment):
  - check spelling in the code with `codespell`
  - check and lint the code with `ruff` + `pylint` + `flake8`
  - check code complexity with `complexipy`
  - use `py_compile` to check that things are correctly written
  - generally, double check your code for good style, ease of understanding, good API / interface, safety and speed
- run tests after each significant code change and before returning to the user if code changes have been done
- use established packages:
  - all python standard library packages are fine to use
  - TODO: list the packages that can be used
  - no more package imports needed; if you think more packages are needed, ask / discuss with the user, then adds these here and to the environment only if the user says yes
- code defensively: use asserts to document and check all assumptions about incoming data
- make sure that the asserts are really useful and not tautological - asserts should really check that the data match what is expected, i.e. check that the input from the "messy real world" (in particular, sd card files written by the logger) match the assumptions about the structure of the file and content
- if you are in doubt, or anything is unclear or ambiguous or badly explained or defined, do not guess - ask me (the user) for more information
- if you can see several ways to implement the same thing, and you are unsure which one to choose, feel free to ask me (the user) for more information / chat together

## Code setup and environment management: mamba

- use mamba; it should be pre installed on the system; do not install it yourself, do not add channels, only conda-forge should be used; fail if no mamba and ask user help
- use an environment.yml to define the necessary packages for the mamba environment
- use, or create if necessary, a dedicated environment for working on this, with name: "TODO: choose a good name"; use only this env for running code here
- use only conda-forge channel (this should already be set by the mamba install available)

## Code architecture and conventions

- magic constants should be ALL_CAPS_CONSTANTS defined at the start to make it easy to edit
- avoid object oriented if not necessary, make the code based on simple functions
- pass the ALL_CAPS_CONSTANTS as default args, it is ok to have many default args to the functions
- make sure to use config files, like some json or csv etc, to summarize config choices, architecture choice for neural networks if there are some, etc; make the code robust and general so that it easily supports running for example several experiments and models, doing bookkeeping to be able to analyze the results a posteriori
- the work is split into independent, consecutive, self contained tasks that each correspond to a python file: run first 00_PLACEHOLDER_FOR_TASK.py, then 01_PLACEHOLDER_FOR_ANOTHER_TASK.py, etc... When generating figures, name them 00p01_PLACEHOLDER_FIGURENAME.png, 00p02_PLACEHOLDER.png for script 00_, etc (02p03_PLACEHOLDER.png for 3rd figure of 2nd script)
- the scripts should be able to run both on a computer with graphical display possibility (then the figures should pop up for the user to interact with them), and on a computer that runs headless (the this should be detected and the figures should only be saved to disk but not pop up as they cannot)
- the README.md should be a quick user-friendly summary of the project and its organization
- when there are several steps in a file, separate these into logical sections with ipython cell markers (`# %%`). Make sure there is such a marker on the first line and last line of each file, so that these are ipython-friendly for users who run it this way.
- save matplotlib figures as `.png`; also show them interactively if a graphical environment is available. Scripts may run headless on servers, so check this at script startup and disable interactive plotting if needed. Name figures according to the file name and IPython section/cell number, for example: `00p01_plot_all_trajectories.png`.

## Misc

- at the end of each update to the code, go through the files and check that the documentation and readme are up to date; make sure all important aspects are documented in the DOCUMENTATION.md file
- when writing code, check that all guidelines present here are followed
- at the end of each code update, do a small review of the code, look for good possibilities for refactoring and improvement, and if there are clear improvement possibilities, work on implementing them
- at the end of each code update, make sure everything works - tests, spell check, linting, py_compile, etc
- if you find a better way to do things, or you have an idea of possible improvement or something better to do (better method, better algorithm, better data structure to use; something more to test and try with the data to see if it can give a better result), discuss this with the user
- the user is typically a PhD level expert on the topic - dont hesitate to discuss, brainstorm, exchange etc with the user on hard questions
- keep a DISCUSSIONS_LOG.md log of the discussions with the user, summarizing prompts, what you did to answer the promt, etc
- if relevant, you can keep a THOUGHTS.md of your own thoughts and things that you want to document to re use for later sessions starting from scratch - important insights etc that do not fit somewhere else
- make sure that your output is both human and ai friendly; in particular, have well formatted logs and outputs that can be read both by human and ai. produce figures to present the output to the human, and also, if relevant (for examle, the figures show or contain some key metrics that are meaninful, or are "just" a few histogram bars), print out in log the summary of the data shown in the figure so the ai can read it without needing to see the figure (this only works if there are small outputs; dont do this with a massive 2d plot, or large trajectory plots etc that contain too much data to be printed in logs).
- when running scripts, run one at a time, wait for it to complete, then run another: be aware of RAM use to not freeze and crash the host machine
- do not store raw prompts/data containing personal or confidential information; redact or summarize minimally, both in the README, DOCUMENTATION, AGENT, or any other file: do not leak credentials or passwords or secrets
- if you notice anything that may look like a leaked secret or a security risk, let the user know immediately
- if writing more languages in the project as a whole, also apply best practices relevant to this language; for example:
  - if writing and running bash scripts, use `shellcheck` (`mamba` installable from conda-forge) and run it on the script, and use best practices (headers to fail on first error etc)
