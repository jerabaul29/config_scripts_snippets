import numpy as np
import pandas as pd

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

data = np.array([[1.1, 1.2, 1.3], [2.1, 2.2, 2.3], [3.1, 3.2, 3.3]])
some_pd = pd.DataFrame(data=data, columns=["some_column", "column_1", "column_2"])
ic(some_pd)

ic(list(some_pd.index))

