import numpy as np
import pandas as pd

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

data = np.array([[1.1, 1.2, 1.3], [2.1, 2.2, 2.3], [3.1, 3.2, 3.3]])
some_pd = pd.DataFrame(data=data, columns=["some_column", "column_1", "column_2"])
ic(some_pd)

# extract one column
ic(some_pd.loc[:, "some_column"])

# extract a list of columns
ic(some_pd.loc[:, ["column_1", "column_2"]])

# extract the rows where a condition is met and re-index
some_pd["flag"] = [True, False, True]
ic(some_pd)
good_rows = ic(some_pd[some_pd["flag"] == True].index.tolist())
ic(some_pd.iloc[good_rows])
ic(some_pd.iloc[good_rows].reset_index())

