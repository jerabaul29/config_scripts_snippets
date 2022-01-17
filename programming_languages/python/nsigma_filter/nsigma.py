import numpy as np


def sliding_filter_nsigma(np_array_in, nsigma=3.0, side_half_width=5, skip_around=4):
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
            np_array[crrt_middle_index] = mean  # we play a bit with fire: simply do a mean interpolation
            list_filtered_indexes.append(crrt_middle_index)

    return np_array, list_filtered_indexes
