import numpy as np
from scipy import stats
import matplotlib.pyplot as plt

import pandas as pd

import seaborn as sns

from icecream import ic

ic.configureOutput(prefix='', outputFunction=print)


############################################################


def self_probability_integral_transform(sample_array_in):
    """Given the sample_array_in empirical samples, get
    the probability integral transform applied on the
    same samples.

    sample_array_in: numpy array, shape (n_samples,)"""

    assert len(sample_array_in.shape) == 1

    n_samples = len(sample_array_in)

    # argsort provides the indexes_sorting such that:
    # sample_array_in[indexes_sorting] is sorted
    # however, what we want to perform the PIT is the index each entry
    # would have when the array gets sorted; this is obtained by applying
    # the inverse permutation to the arange of indexes
    indexes_sorting = np.argsort(sample_array_in)
    inverse_indexes_sorting = np.empty_like(indexes_sorting)
    inverse_indexes_sorting[indexes_sorting] = np.arange(n_samples)
    pit_transformed = np.arange(1, n_samples+1, 1)[inverse_indexes_sorting] / n_samples

    ic(np.min(pit_transformed))
    ic(np.max(pit_transformed))

    return pit_transformed

############################################################

mvnorm = stats.multivariate_normal(mean=[0, 0], cov=[[1., 0.7],
                                                     [0.7, 1.]])
x = mvnorm.rvs(1000)

############################################################
# vanilla jointplot by setting the x and y arrays explicitly
# sns.jointplot(x=x[:, 0], y=x[:, 1], kind='hex')

############################################################
# vanilla jointplot by setting the x and y arrays be pd name
dataframe_2d = pd.DataFrame(data=x, columns=["x0", "x1"])

sns.jointplot(data=dataframe_2d, x="x0", y="x1", kind="hex")

############################################################
# view as a copula like PIT-transformed jointplot

# compute the data PIT transformed so that marginals are uniform
for crrt_column in ["x0", "x1"]:
    crrt_data = dataframe_2d.loc[:, crrt_column].to_numpy(dtype=np.float32)
    crrt_data_pit_transformed = self_probability_integral_transform(crrt_data)
    new_column_name = crrt_column + "_uniformized"
    dataframe_2d[new_column_name] = crrt_data_pit_transformed

ic(dataframe_2d)

sns.jointplot(data=dataframe_2d, x="x0_uniformized", y="x1_uniformized", kind="hex", xlim=(0.0, 1.0), ylim=(0.0, 1.0))

############################################################
plt.show()

