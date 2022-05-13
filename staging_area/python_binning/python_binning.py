import numpy as np

from typing import Tuple

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)


def bin_data(np_array_in: np.ndarray, nbr_bins: int) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Get bins for binning the data, large enough that no edge effect issues - will always be possible
    to find right bin using np.searchsorted on the output bin edges.

    Arguments:
        np_array_in: the data to bin
        nbr_bins: the nbr of bins to use

    Returns:
        bin_limits: the limits of the bins; will be nbr_bins+1 long
        bin_mids: the middle of the bins; will be nbr_bins long
        array_bin_indexes: which bin each of the entries in np_array_in should got to; will be same
            length as np_array_in

    example of use:

    ```
    nbr_bins = 20

    bin_limits, bin_mids, array_bin_indexes = get_bins(some_array, nbr_bins)

    dict_entries_in_their_bin = {}
    for crrt_bin in range(nbr_bins):
        dict_entries_in_their_bin[crrt_bin] = []

    for crrt_bin_index, crrt_entry in enumerate(array_bin_indexes, some_array):
        dict_entries_in_their_bin[crrt_bin_index].append(crrt_entry)
    ```

    NOTES:
        could possibly be (partly) rewritten with np.digitize
        we already use np.searchsorted for speed
    """

    assert len(np_array_in.shape) == 1, "only implemented for input arrays of size 1"
    assert nbr_bins > 0, "need a positive number of bins"

    val_min = np.min(np_array_in)
    val_max = np.max(np_array_in)

    # need a bit wider bins
    if val_min == 0:
        val_min = -val_max * 0.001
    elif val_min >= 0:
        val_min = val_min * 0.99
    else:
        val_min = val_min * 1.01

    if val_max == 0:
        val_max = -val_min * 0.001
    elif val_max >= 0:
        val_max = val_max * 1.01
    else:
        val_max = val_max * 0.99

    bin_width = (val_max - val_min) / nbr_bins
    bin_limits = np.arange(val_min, val_max+bin_width/2.0, bin_width)
    bin_mids = (bin_limits[:-1] + bin_limits[1:]) / 2.0

    array_bin_indexes = np.searchsorted(bin_limits, np_array_in, side="left")

    return (bin_limits, bin_mids, array_bin_indexes)


array_test = np.array([34.5, 2.0, 23.3, 9.5, 11, 12, 14, 13, 13.9, 27.3])
nbr_bins = 4
bin_limits, bin_mids, array_bin_indexes = bin_data(array_test, nbr_bins)

ic(array_test)
ic(nbr_bins)
ic(bin_limits)
ic(bin_mids)
ic(array_bin_indexes)

