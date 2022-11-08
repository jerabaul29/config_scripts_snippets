import numpy as np
import pandas as pd

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

############################################################
# create an empty pandas and append entries to it

# main pandas
big_pandas = pd.DataFrame(columns=["c0", "c1", "c2"])
ic(big_pandas)

# create a small pandas from numpy arrays
# in numpy, we write line after line
some_rows = np.array([[0.0, 0.1, 0.2], [1.0, 1.1, 1.2]])
ic(some_rows)
ic(some_rows.shape)
small_pandas = pd.DataFrame(data=some_rows, columns=["c0", "c1", "c2"])
ic(small_pandas)

# append to the main pandas
big_pandas = pd.concat([big_pandas, small_pandas], ignore_index=True)
ic(big_pandas)

# do it once more
some_new_rows = np.array([[2.0, 2.1, 2.2], [3.0, 3.1, 3.2]])
small_pandas = pd.DataFrame(data=some_new_rows, columns=["c0", "c1", "c2"])
big_pandas = pd.concat([big_pandas, small_pandas], ignore_index=True)
ic(big_pandas)

