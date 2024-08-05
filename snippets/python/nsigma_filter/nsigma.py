import numpy as np


def sliding_filter_nsigma(np_array_in, nsigma=3.0, side_half_width=5, skip_around=2):
    """Perform a sliding filter, on points of indexes
    [idx-side_half_width-skip_around; idx-skip_around] + [idx+skip_around; idx+side_half_width+skip_around],
    to remove outliers. I.e.,
    the [idx] point gets removed if it is more than nsigma deviations away
    from the mean of the whole segments around it, ignoring a few neighboring
    points. this allows to filter out local peaks, even if they have a bit of self correlation.

    np_array_in should have a shape (nbr_of_entries,).

    return the filtered array and the list of indexes where filtered out

    """

    np_array = np.copy(np_array_in)
    array_len = np_array.shape[0]

    list_filtered_indexes = []

    middle_point_index_start = side_half_width
    middle_point_index_end = array_len - side_half_width - 1

    for crrt_middle_index in range(middle_point_index_start, middle_point_index_end+1, 1):
        crrt_left_included = crrt_middle_index - side_half_width - skip_around
        crrt_right_included = crrt_middle_index + side_half_width + skip_around
        crrt_array_data = np.concatenate([np_array_in[crrt_left_included:crrt_middle_index-skip_around], np_array_in[crrt_middle_index+1+skip_around:crrt_right_included+1]])
        mean = np.mean(crrt_array_data)
        std = np.std(crrt_array_data)
        if np.abs(np_array[crrt_middle_index] - mean) > nsigma * std:
            np_array[crrt_middle_index] = mean  # we play a bit with fire: simply do a mean interpolation; could also put simply NaN
            list_filtered_indexes.append(crrt_middle_index)

    return np_array, list_filtered_indexes


def indexes_nsigma_outlier(np_array_in, n_sigma=5.0):
    """Perform nsigma filtering of the 1D array np_array_in,
    returning the boolean array indicating which points pass
    the nsigma test.

    IN:
        np_array_in: numpy array, shape (n_samples,)
        n_sigma: the threshold for rejecting data

    OUT:
        array_nsigma_validity: array of booleans indicating
            for each point if it passed the nsigma test or not;
            ie True indicates a valid point, False an outlier
            according to the nsigma filter. shape (n_samples,)
    """
    sigma = np.std(np_array_in)
    mean = np.mean(np_array_in)
    array_nsigma_validity = (np.abs(np_array_in - mean) < n_sigma * sigma)

    return array_nsigma_validity


def indexes_both_valid(np_array_1, np_array_2, n_sigma=5.0):
    """Perform joint nsigma filtering of np_array_1 and np_array_2, i.e.
    return the array of indexes which pass the nsigma test for both
    np_array_1 and np_array_2.

    IN:
        np_array_1: numpy array, shape (n_samples,)
        np_array_2: numpy array, shape (n_samples,)
        n_sigma: the threshold for rejecting data

    OUT:
        co_valid: array of booleans indicating
            for each point if it passed the nsigma test or not;
            on both np_array_1 and np_array_2 at this index;
            ie True indicates a valid point at this index for
            both np_array_1 and np_array_2, False an outlier
            according to the nsigma filter in at least one of
            them. shape (n_samples,)
    """
    valid_1 = indexes_nsigma_outlier(np_array_1, n_sigma=n_sigma)
    valid_2 = indexes_nsigma_outlier(np_array_2, n_sigma=n_sigma)

    # note: the logical_and reduce make it easy to add as many inputs as wanted
    co_valid = np.logical_and.reduce(
        (
            valid_1,
            valid_2,
        )
    )

    return co_valid
