from pathlib import Path
import git

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

crrt_repo = git.Repo(Path.cwd(), search_parent_directories=True)
ic(crrt_repo)
commit_sha = crrt_repo.head.object.hexsha
ic(commit_sha)
