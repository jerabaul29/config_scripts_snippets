import numpy as np

from scipy import interpolate

import matplotlib.pyplot as plt

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

    return pit_transformed


def get_linear_probability_integral_transforms(sample_array_in, minux_max=-1.0e37, plus_max=1.0e37, max_n_points=50000):
    """Given the sample_array_in empirical samples, get
    the linear transforms that fulfills the PIT theory,
    in the forward and backwards directions.

    sample_array_in: numpy array, shape (n_samples, )
    minux_max: for learning the transform, the smallest value to be expected for sample_array_in
    plus_max: for learning the transform, the largest value to be expected for sample_array_in
    max_n_points: max number of points to use in the linear interpolation; if the sample_array_in has
        more than max_n_points, will remove randomly some of the points

    forward_transform: the linear transform to apply the PIT
        based on linear transformation of the data; i.e.:
            forward_transform: [domain of sample_array_in] -> [0, 1]
    backwards_transform: the linear transform to apply the
        reverse PIT based on linear transformation of the
        data; i.e.:
            backwards_transform: [0, 1] -> [domain of sample_array_in]
    """
    assert len(sample_array_in.shape) == 1

    if sample_array_in.shape[0] > max_n_points:
        # shuffle randomly
        permutation = np.random.permutation(np.arange(0, sample_array_in.shape[0]))
        sample_array_in = sample_array_in[permutation]

        # keep only the given number of points
        sample_array_in = sample_array_in[:max_n_points]

    max_extremes = np.array([minux_max, plus_max])
    extended_samples_array_in = np.concatenate((sample_array_in, max_extremes))

    # avoid duplicates in the data - we want a monotonic transform
    unique_extended_samples = np.unique(extended_samples_array_in)

    n_samples = len(unique_extended_samples)

    pit_values = np.linspace(0.0, 1.0, n_samples)

    # ie the transform we just learnt is:
    # unique_extended_samples -> pit_values
    # corresponding to forward_transform
    # and backwards_transform is:
    # pit_values -> unique_extended_samples

    forward_transform = interpolate.interp1d(unique_extended_samples, pit_values, kind='linear', copy=True, bounds_error=True, assume_sorted=False)
    backwards_transform = interpolate.interp1d(pit_values, unique_extended_samples, kind='linear', copy=True, bounds_error=True, assume_sorted=False)

    return forward_transform, backwards_transform

if __name__ == '__main__':
    mu, sigma = 0, 0.1 # mean and standard deviation
    s = np.random.normal(mu, sigma, 1000000)
    forward_transform, backwards_transform = get_linear_probability_integral_transforms(s)

    plt.figure()
    sns.histplot(s)
    plt.xlabel("native s")

    plt.figure()
    sns.histplot(forward_transform(s))
    plt.xlabel("forward_transform(s)")

    plt.figure()
    sns.histplot(backwards_transform(forward_transform(s)))
    plt.xlabel("backwards_transform(forward_transform(s)")

    plt.show()

