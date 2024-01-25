import time
import os

# ------------------------------------------------------------------------------------------
print("***** Put the interpreter in UTC, to make sure no TZ issues")
os.environ["TZ"] = "UTC"
time.tzset()

from icecream import ic

import datetime
import pytz

import numpy as np

utc_timezone = pytz.timezone("UTC")

ic.configureOutput(prefix="", outputFunction=print)

# np timestamp from string
print("")
print("--- np timestamp from string")
utc_string = "2012-06-17T23:00:05.45300000Z"
utc_np = np.datetime64(utc_string)
ic(utc_string)
ic(utc_np)

# datetime to np timestamp
print("")
print("--- np timestamp from datetime")
some_datetime = datetime.datetime.utcnow()
some_datetime = utc_timezone.localize(some_datetime)
np_datetime = np.datetime64(some_datetime)
ic(some_datetime)
ic(np_datetime)

# np timestamp to datetime
print("")
print("--- datetime from np timestamp")
ic(utc_np)
print(f"{utc_np = }")
# do the conversion from np.timestamp to datetime.datetime
datetime_from_np = datetime.datetime.utcfromtimestamp(int(utc_np)/1e9)
# localize to UTC if you want a timezone aware
datetime_from_np = utc_timezone.localize(datetime_from_np)
ic(datetime_from_np)

