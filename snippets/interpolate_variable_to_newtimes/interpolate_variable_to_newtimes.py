import numpy as np
import scipy as sp


def interpolate_variable_to_newtimes(times: np.ndarray[np.datetime64],
                                     variable_on_times: np.ndarray,
                                     newtimes: np.ndarray[np.datetime64],
                                     timegap_max: np.datetime64 = np.timedelta64(3, "h"),
                                     max_order: int = 1) -> np.ndarray:
    """Interpolate a time dependent variable to a new set of times. This is
    done in such a way that, for each new interpolation time, only data within
    [newtime-timegap_max; newtime+timegap_map], are considered. This allows
    to perform robust interpolation even if there are holes in the initial
    timeseries. At each new time, the function returns either NaN if there
    are no samples within timegap_max, or the nearest value if there is only
    1 neighbor (order 0) within timegap_max, or the linear interpolated value
    (order 1) if there are 2 neighbors or more within timegap_max with 1 on
    each side (as long as this is allowed by the max_order argument).

    TODO: allow also higher order estimates, IF there are enough points around

    The main point is to enable reasonably good interpolation that is robust.
    
    Arguments
        - times: the times on which the variable is sampled; need to
            be sorted except for the NaT values
        - variable_on_times: the value of the variable on times; needs
            to have the same length as times
        - newtimes: the new times on which to interpolate the variable
        - timegap_map: the maximum time gap between an element of newtimes
            and an elemet of times to use the element of times in the
            interpolation.
        - max_order: the maximum interpolation order. 0: use nearest data;
            1: use linear interpolation.
            
    Output
        - newtimes_interp: the interpolated variable."""

    assert len(times) == len(variable_on_times)

    valid_times = np.logical_and(
        np.isfinite(times),
        np.isfinite(variable_on_times),
    )
    variable_on_times = variable_on_times[valid_times]
    times = times[valid_times]

    assert np.all(times[:-1] <= times[1:])

    valid_newtimes = np.isfinite(newtimes)
    full_newtimes = newtimes
    newtimes = newtimes[valid_newtimes]

    there_is_a_time_close_before_newtime = np.full((len(newtimes),), False)

    for crrt_ind, crrt_newtime in enumerate(newtimes):
        difference = crrt_newtime - times
        there_is_a_time_close_before_newtime[crrt_ind] = np.any(
            np.logical_and(
                difference > np.timedelta64(0, "ns"),
                difference < timegap_max
            )
        )

    there_is_a_time_close_after_newtime = np.full((len(newtimes),), False)

    for crrt_ind, crrt_newtime in enumerate(newtimes):
        difference = times - crrt_newtime
        there_is_a_time_close_after_newtime[crrt_ind] = np.any(
            np.logical_and(
                difference > np.timedelta64(0, "ns"),
                difference < timegap_max
            )
        )

    # interpolation only takes real coordinates
    times_ns_to_s = times.astype('datetime64[ns]').astype(np.float64) / 1e9
    newtimes_ns_to_s = newtimes.astype('datetime64[ns]').astype(np.float64) / 1e9

    newtimes_interp_nearest = sp.interpolate.interp1d(times_ns_to_s, variable_on_times, kind="nearest", bounds_error=False, fill_value="extrapolate")(newtimes_ns_to_s)

    if max_order > 0:
        newtimes_interp_linear = sp.interpolate.interp1d(times_ns_to_s, variable_on_times, kind="linear", bounds_error=False, fill_value="extrapolate")(newtimes_ns_to_s)

    # array of interpolated as linearly interpolated
    newtimes_interp = np.full(np.shape(newtimes), np.nan)

    closest_valid = np.logical_or(there_is_a_time_close_before_newtime, there_is_a_time_close_after_newtime)
    newtimes_interp[closest_valid] = newtimes_interp_nearest[closest_valid]

    if max_order > 0:
        linear_valid = np.logical_and(there_is_a_time_close_before_newtime, there_is_a_time_close_after_newtime)
        newtimes_interp[linear_valid] = newtimes_interp_linear[linear_valid]

    full_newtimes_interp = np.full(np.shape(full_newtimes), np.nan)
    full_newtimes_interp[valid_newtimes] = newtimes_interp

    return full_newtimes_interp


def test_interpolate_variable_to_newtimes_order_0():
    times = np.array(
        [
            np.datetime64("2024-09-17T12:00:00"),
            np.datetime64("2024-09-17T20:00:00"),
            np.datetime64("2024-09-17T21:00:00"),
            np.datetime64("2024-09-18T12:00:00"),
            np.datetime64("2024-09-18T13:00:00"),
            np.datetime64("2024-09-18T14:00:00"),
            np.datetime64("2024-09-18T15:00:00"),
        ]
    )

    variable_on_times = np.array(
        [
            0,
            10,
            11,
            100,
            200,
            np.nan,
            400,
        ]
    )

    newtimes = np.array(
        [
            np.datetime64("NaT"),
            np.datetime64("2024-09-17T06:00:00"),
            np.datetime64("2024-09-17T11:00:00"),
            np.datetime64("2024-09-17T13:00:00"),
            np.datetime64("2024-09-17T16:00:00"),
            np.datetime64("2024-09-17T19:00:00"),
            np.datetime64("2024-09-17T20:00:00"),
            np.datetime64("2024-09-17T20:29:00"),
            np.datetime64("2024-09-18T13:00:00"),
            np.datetime64("2024-09-18T13:30:00"),
            np.datetime64("2024-09-18T13:59:00"),
            np.datetime64("2024-09-18T15:00:00"),
            np.datetime64("NaT"),
            np.datetime64("2024-09-18T16:00:00"),
            np.datetime64("2024-09-18T20:00:00"),
            np.datetime64("NaT"),
        ]
    )

    expected = np.array(
        [
            np.nan,
            np.nan,
            0,
            0,
            np.nan,
            10,
            10,
            10,
            200,
            200,
            200,
            400,
            np.nan,
            400,
            np.nan,
            np.nan,
        ]
    )

    result = interpolate_variable_to_newtimes(times, variable_on_times, newtimes, max_order=0)

    # print(f"{result}")
    # print(f"{expected}")

    assert ((result == expected) | (np.isnan(result) & np.isnan(expected))).all()


def test_interpolate_variable_to_newtimes_order_1():
    times = np.array(
        [
            np.datetime64("2024-09-17T12:00:00"),
            np.datetime64("2024-09-17T20:00:00"),
            np.datetime64("2024-09-17T21:00:00"),
            np.datetime64("2024-09-18T12:00:00"),
            np.datetime64("2024-09-18T13:00:00"),
            np.datetime64("2024-09-18T14:00:00"),
            np.datetime64("2024-09-18T15:00:00"),
        ]
    )

    variable_on_times = np.array(
        [
            0,
            10,
            11,
            100,
            200,
            np.nan,
            400,
        ]
    )

    newtimes = np.array(
        [
            np.datetime64("NaT"),
            np.datetime64("2024-09-17T06:00:00"),
            np.datetime64("2024-09-17T11:00:00"),
            np.datetime64("2024-09-17T13:00:00"),
            np.datetime64("2024-09-17T16:00:00"),
            np.datetime64("2024-09-17T19:00:00"),
            np.datetime64("2024-09-17T20:00:00"),
            np.datetime64("2024-09-17T20:29:00"),
            np.datetime64("2024-09-18T13:00:00"),
            np.datetime64("2024-09-18T13:30:00"),
            np.datetime64("2024-09-18T14:00:00"),
            np.datetime64("2024-09-18T15:00:00"),
            np.datetime64("NaT"),
            np.datetime64("2024-09-18T16:00:00"),
            np.datetime64("2024-09-18T20:00:00"),
            np.datetime64("NaT"),
        ]
    )

    expected = np.array(
        [
            np.nan,
            np.nan,
            0,
            0,
            np.nan,
            10,
            10,
            10.5,
            200,
            250,
            300,
            400,
            np.nan,
            400,
            np.nan,
            np.nan,
        ]
    )

    result = interpolate_variable_to_newtimes(times, variable_on_times, newtimes, max_order=1)

    # print(f"{result}")
    # print(f"{expected}")

    assert ((np.abs(result - expected) < 0.1) | (np.isnan(result) & np.isnan(expected))).all()


if __name__ == "__main__":
    test_interpolate_variable_to_newtimes_order_0()
    test_interpolate_variable_to_newtimes_order_1()
