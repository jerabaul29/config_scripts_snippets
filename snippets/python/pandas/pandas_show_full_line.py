import numpy as np
import pandas as pd

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

data = np.array([[1.1, 1.2, 1.3], [2.1, 2.2, 2.3], [3.1, 3.2, 3.3]])
some_pd = pd.DataFrame(data=data, columns=["some_column", "column_1", "column_2"])
ic(some_pd)

# option 1: force to print as string; that may be a bit ugly in jupyter though...
print(some_pd.loc[0, :].to_string())

# another option: set the option
pd.set_option('display.max_columns', None)
pd.set_option('display.max_rows', None)

