from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

some_var = 42
some_other_var = 43

stringname = "some_var"
ic(stringname)
ic(globals()[stringname])

