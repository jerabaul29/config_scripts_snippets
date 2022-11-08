import numpy as np
from scipy import stats
import matplotlib.pyplot as plt

import pandas as pd

import seaborn as sns

from icecream import ic

ic.configureOutput(prefix='', outputFunction=print)


############################################################
# utilities from https://github.com/stochasticresearch/copula-py/blob/master/ecdf.py

from scipy.interpolate import interp1d


def ecdf(x_i, npoints):
    """ Generates an Empirical CDF using the indicator function.

    Inputs:
    x_i -- the input data set, should be a numpy array
    npoints -- the number of desired points in the empirical CDF estimate

    Outputs:
    y -- the empirical CDF
    """
    # define the points over which we will generate the kernel density estimate
    x = np.linspace(min(x_i), max(x_i), npoints)
    n = float(x_i.size)
    y = np.zeros(npoints)

    for ii in np.arange(x.size):
        idxs = np.where(x_i<=x[ii])
        y[ii] = np.sum(idxs[0].size)/n

    return (x,y)


def probability_integral_transform(X):
    """
    Takes a data array X of dimension [M], ie M samples, and converts it to a uniform
    random variable using the probability integral transform, U = F(X)
    """
    M = X.shape[0]

    # convert X to U by using the probability integral transform:  F(X) = U
    U = np.empty(X.shape)

    # estimate the empirical cdf
    (xx, pp) = ecdf(X, M)
    f = interp1d(xx, pp, kind="nearest")

    # plug this RV sample into the empirical cdf to get uniform RV
    u = f(X)

    return u

############################################################

mvnorm = stats.multivariate_normal(mean=[0, 0], cov=[[1., 0.5],
                                                     [0.5, 1.]])
x = mvnorm.rvs(1000)

# vanilla plot
sns.jointplot(x=x[:, 0], y=x[:, 1], kind='kde', stat_func=None)

# more fancy plot with pandas
dataframe_2d = pd.DataFrame(data=x, columns=["x0", "x1"])

sns.jointplot(data=dataframe_2d, x="x0", y="x1", kind="kde")

# view as a copula
# compute the data resampled so that marginals are uniform
for crrt_column in ["x0", "x1"]:
    crrt_data = dataframe_2d.loc[:, crrt_column].to_numpy(dtype=np.float32)
    crrt_data_uniformized = probability_integral_transform(crrt_data)
    new_column_name = crrt_column + "_uniformized"
    dataframe_2d[new_column_name] = crrt_data_uniformized

ic(dataframe_2d)

sns.jointplot(data=dataframe_2d, x="x0_uniformized", y="x1_uniformized", kind="kde")

plt.show()

