# %%

# exit()

# %%

# ipython3 --pdb
# ipython3

# %%

# %reset -f

# %%

import numpy as np

from typing import List
import numpy.typing as npt

# %%


def insert_NaNs_in_time_holes(
    common_time_index: npt.NDArray[np.datetime64],
    hole_threshold: np.timedelta64,
    list_data_arrays: List[npt.NDArray],
    data_arrays_time_index: int = 0):
    """Insert NaNs where holes are detected in common_time_index. This is useful, for example,
    to fill holes with NaNs before plotting to avoid ugly lines on the plots.

    Args:
        common_time_index: the time index, should be common to all arrays in list_data_arrays
        hole_threshold: the threshold over which we consider that there
            is a hole. The NaNs will be filled at start_hole + hole_threshold/4 and
            end_hole - hole_threshold/4 , for each hole
        list_data_arrays: a list of the data arrays using the common_time_index
        data_arrays_time_index: the index used for time in the arrays within list_data_arrays

    Returns:
        (new_common_time_index, list_new_data_arrays): new_time_index is a new time index (i.e.
            a separate copy) with the start and ends of NaN periods inserted,
                                                       list_new_data_arrays is a new list of
            data arrays (i.e. separate copies) with the NaN hole delimiters inserted.
    """

    # common_time_index should be datetime64 and increasing
    assert np.issubdtype(common_time_index.dtype, np.datetime64)
    assert np.all(np.diff(common_time_index)) >= 0

    hole_threshold = hole_threshold.astype('timedelta64[ns]')

    # each list_data_arrays array should have a time dimension equal to common_time_index
    for crrt_data_array in list_data_arrays:
        assert np.shape(crrt_data_array)[data_arrays_time_index] == np.shape(common_time_index)[0]

    time_deltas = common_time_index[1:] - common_time_index[:-1]
    time_jump_indexes = np.where(time_deltas > hole_threshold)[0]

    time_hole_starts = common_time_index[time_jump_indexes] + hole_threshold / 4
    time_hole_ends = common_time_index[time_jump_indexes+1] - hole_threshold / 4
    # intertwindle the 2
    time_hole_limits = np.dstack((time_hole_starts, time_hole_ends)).flatten()

    time_jump_indexes = np.repeat(time_jump_indexes, 2)

    new_common_time_index = np.insert(common_time_index, time_jump_indexes+1, time_hole_limits)

    list_new_data_arrays = []
    for crrt_data_array in list_data_arrays:
        to_insert = np.transpose(np.nan*crrt_data_array[0])
        new_crrt_data_array = np.insert(crrt_data_array, time_jump_indexes+1, to_insert, data_arrays_time_index)
        list_new_data_arrays.append(new_crrt_data_array)

    return (new_common_time_index, list_new_data_arrays)

# %%

# example / test
# TODO: if moving to dedicated functionality, make this into the associated tests

common_time_index = np.array(
    [
        np.datetime64("2024-01-01T00:00:00"),
        np.datetime64("2024-01-01T01:00:00"),
        np.datetime64("2024-01-01T06:00:00"),
        np.datetime64("2024-01-01T07:00:00"),
        np.datetime64("2024-01-01T08:00:00"),
        np.datetime64("2024-01-01T09:00:00"),
        np.datetime64("2024-01-01T12:00:00"),
        np.datetime64("2024-01-01T13:00:00"),
        np.datetime64("2024-01-01T13:30:00"),
    ]
)

expected_new_common_time_index = np.array(
    [
        np.datetime64("2024-01-01T00:00:00"),
        np.datetime64("2024-01-01T01:00:00"),
        np.datetime64("2024-01-01T01:30:00"),
        np.datetime64("2024-01-01T05:30:00"),
        np.datetime64("2024-01-01T06:00:00"),
        np.datetime64("2024-01-01T07:00:00"),
        np.datetime64("2024-01-01T08:00:00"),
        np.datetime64("2024-01-01T09:00:00"),
        np.datetime64("2024-01-01T09:30:00"),
        np.datetime64("2024-01-01T11:30:00"),
        np.datetime64("2024-01-01T12:00:00"),
        np.datetime64("2024-01-01T13:00:00"),
        np.datetime64("2024-01-01T13:30:00"),
    ]
)

hole_threshold = np.timedelta64(2, "h")

list_data_arrays = [
    np.array([1, 2, 5, 6, 7, 8, 11, 12, 13]).astype('float'),
    np.array([10, 20, 50, 60, 70, 80, 110, 120, 130]).astype('float'),
    np.array([[1,0], [2,0], [5,0], [6,0], [7,0], [8,0], [11,0], [12,0], [13,0],]).astype('float'),
]

expected_list_new_data_arrays = [
    np.array([1, 2, np.nan, np.nan, 5, 6, 7, 8, np.nan, np.nan, 11, 12, 13]).astype('float'),
    np.array([10, 20, np.nan, np.nan, 50, 60, 70, 80, np.nan, np.nan, 110, 120, 130]).astype('float'),
    np.array([[1,0], [2,0], [np.nan,np.nan], [np.nan,np.nan], [5,0], [6,0], [7,0], [8,0], [np.nan,np.nan], [np.nan,np.nan], [11,0], [12,0], [13,0],]).astype('float'),
]

data_arrays_time_index = 0

(new_common_time_index, list_new_data_arrays) = insert_NaNs_in_time_holes(common_time_index, hole_threshold, list_data_arrays)


def compare_np_arrays_with_nan(a, b, epsilon=1.0e-12):
    """Given 2 arrays of floats, check for corresponding indexes that either both have values close to
    each other at epsilon prediction, or both have nans."""
    res = np.logical_or(
        np.abs(a - b) < epsilon,
        np.logical_and(np.isnan(a), np.isnan(b))
    ).all()
    return res


assert np.all(new_common_time_index == expected_new_common_time_index)
assert compare_np_arrays_with_nan(list_new_data_arrays[0], expected_list_new_data_arrays[0])
assert compare_np_arrays_with_nan(list_new_data_arrays[1], expected_list_new_data_arrays[1])
assert compare_np_arrays_with_nan(list_new_data_arrays[2], expected_list_new_data_arrays[2])

# %%
