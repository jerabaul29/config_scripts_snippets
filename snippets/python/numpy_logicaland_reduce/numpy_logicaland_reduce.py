import numpy as np

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

some_array_1 = np.array([1, 1, 3, 9, 4, 7, 1])
some_array_2 = np.array([0, 1, 0, 1, 0, 0, 1])
some_array_3 = np.array([5, 3, 8, 9, 3, np.nan, 1])

indexes_fit = np.logical_and.reduce(
    (
        some_array_1 < 8,
        some_array_2 == 0,
        np.isfinite(some_array_3),
    )
)

ic(some_array_1 <          8)
ic(some_array_2 ==         0)
ic(np.isfinite(some_array_3))
print("              ", end=""); ic(indexes_fit)
