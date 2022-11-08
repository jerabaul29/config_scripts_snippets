import numpy as np
import pandas as pd
from icecream import ic

ic.configureOutput(prefix='', outputFunction=print)

dummy_array = np.array([1.1, 2.2, 3.3, 4.4, 5.5])
ic(dummy_array)

# convert from numpy to pandas
dummy_array_df = pd.DataFrame(data=dummy_array, columns=["data"])
ic(dummy_array_df)

# convert from pandas to numpy
dummy_array_back = dummy_array_df.to_numpy(dtype=np.float32)
ic(dummy_array_back)

