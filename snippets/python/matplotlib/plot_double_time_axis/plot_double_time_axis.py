import datetime

import numpy as np

import matplotlib
import matplotlib.pyplot as plt
import matplotlib.dates as mpltdates

import time
import os

import pytz

from icecream import ic

from typing import Callable

# ------------------------------------------------------------------------------------------
print("***** Put the interpreter in UTC, to make sure no TZ issues")
os.environ["TZ"] = "UTC"
time.tzset()
utc_timezone = pytz.timezone("UTC")

# ------------------------------------------------------------------------------------------
ic.configureOutput(outputFunction=print, prefix="")

# ------------------------------------------------------------------------------------------
# converter functions back and forth for the axis


def converter_mpltdate_to_elapsed_totalsecs(datetime_start: datetime.datetime, crrt_mpltdate: matplotlib.dates) -> float:
    return (mpltdates.num2date(crrt_mpltdate)-datetime_start).total_seconds()


def converter_elapsed_totalsecs_to_mpltdate(datetime_start: datetime.datetime, elapsed_totalsecs: float) -> matplotlib.dates:
    return mpltdates.date2num(datetime_start + datetime.timedelta(seconds=elapsed_totalsecs))


vec_converter_mpltdate_to_elapsed_totalsecs = np.vectorize(converter_mpltdate_to_elapsed_totalsecs)
vec_converter_elapsed_totalsecs_to_mpltdate = np.vectorize(converter_elapsed_totalsecs_to_mpltdate)


def supplyer_mpltdates_to_secs(datetime_start: datetime.datetime) -> Callable[[np.ndarray], np.ndarray]:
    def mpltdates_to_secs(arr_mpltdates: np.ndarray) -> np.ndarray:
        if arr_mpltdates.size == 0:
            return np.array([])
        return vec_converter_mpltdate_to_elapsed_totalsecs(datetime_start, arr_mpltdates)

    return mpltdates_to_secs


def supplyer_secs_to_mpltdates(datetime_start: datetime.datetime) -> Callable[[np.ndarray], np.ndarray]:
    def secs_to_mpltdates(arr_secs: np.ndarray) -> np.ndarray:
        if arr_secs.size == 0:
            return np.array([])
        return vec_converter_elapsed_totalsecs_to_mpltdate(datetime_start, arr_secs)

    return secs_to_mpltdates


# ------------------------------------------------------------------------------------------
# an example

# what we want to plot

# we may not have the time_seconds vector initially, but here using it for simplicity of generating the signal
time_seconds = np.arange(0, 10.0, 1)
# signal to plot
signal_cos = np.cos(time_seconds * 2 * np.pi / 7.0)
# the datetime time base; this may actually be the only time base we have initially
time_datetime = [utc_timezone.localize(datetime.datetime.utcnow()) + datetime.timedelta(seconds=i) for i in list(time_seconds)]

ic(time_seconds)
ic(time_datetime)

# how to plot

fig, ax = plt.subplots(constrained_layout=True)

ax.plot(time_datetime, signal_cos)
ax.tick_params(axis='x', labelrotation=45)
ax.set_ylabel("value")

secax = ax.secondary_xaxis(
    'top',
    functions=(supplyer_mpltdates_to_secs(time_datetime[0]), supplyer_secs_to_mpltdates(time_datetime[0]))
)
secax.set_xlabel("time [s]")

plt.tight_layout()
plt.show()
