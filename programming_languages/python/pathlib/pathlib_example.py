"""For more about pathlib, see: https://docs.python.org/3/library/pathlib.html .

A few common cases under."""

from pathlib import Path

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

cwd = Path.cwd()
ic(cwd)

some_cousin_path = cwd.parent / "icecream"
ic(some_cousin_path)

py_in_dir = list(some_cousin_path.glob("*.py"))
ic(py_in_dir)

py_txt_suffix = py_in_dir[0].with_suffix(".txt")
ic(py_txt_suffix)

suffix_txt = py_txt_suffix.suffix
ic(suffix_txt)

crrt_is_file = (cwd / "pathlib_example.py").is_file()
ic(crrt_is_file)

crrt_filename = (cwd / "some_name.ext").name
ic(crrt_filename)

