import numpy as np

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

some_int = 42
some_array = np.array([1, 2, 3])

ic(isinstance(some_int, int))
ic(isinstance(some_int, float))
ic(isinstance(some_array, np.ndarray))

