from pickle_cpickle import cpkl_load_or_generate

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)


@cpkl_load_or_generate
def yet_another_factory(a, b):
    return [a, b]


ic(yet_another_factory(5, 6))
ic(yet_another_factory(5, 6))
ic(yet_another_factory(7, 6))
