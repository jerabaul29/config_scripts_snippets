import time
import os

# ------------------------------------------------------------------------------------------
print("***** Put the interpreter in UTC, to make sure no TZ issues")
os.environ["TZ"] = "UTC"
time.tzset()

from icecream import ic

import datetime
import pytz

utc_timezone = pytz.timezone("UTC")

ic.configureOutput(prefix="", outputFunction=print)

# ------------------------------------------------------------------------------------------
# Make your life easier, use some timezone aware datetimes... When working in science, just use UTC

# we can set the timezone from the constructor
some_utc_datetime_tz_aware = datetime.datetime(2022, 1, 2, 3, 4, 5, 678901, tzinfo=utc_timezone)
ic(some_utc_datetime_tz_aware)
ic(some_utc_datetime_tz_aware.isoformat())

# or apply it later on if the constructor we use cannot do it for us
crrt_utc_tz_aware = utc_timezone.localize(datetime.datetime.utcnow())
ic(crrt_utc_tz_aware)

# converting to another time zone is simple
cet_timezone = pytz.timezone("CET")
crrt_utc_as_cet = crrt_utc_tz_aware.astimezone(cet_timezone)
ic(crrt_utc_as_cet)
ic(crrt_utc_tz_aware)

# ------------------------------------------------------------------------------------------
# don t get confused: second is the second value of the datetime object or timedelta object;
# so, if a timedelta is 2 days and 30 seconds, it will be 30; total_seconds is the
# total number of seconds in a timedelta, i.e. converting to seconds also other fields
# than seconds

time_1 = ic(datetime.datetime(2022, 1, 1, 1, 1, 1, tzinfo=utc_timezone))
time_2 = ic(time_1 + datetime.timedelta(seconds=30) + datetime.timedelta(days=2))
ic(time_2.second)
ic((time_2 - time_1).seconds)
ic((time_2 - time_1).total_seconds())

# ------------------------------------------------------------------------------------------
# note that, even if the os environ is set as utc, if you want to safely change back
# and forth between datetime and timestamp, you need to use the correct functions!

# this works, but really, please, do not take the chance!!
# some_utc = datetime.datetime(2022, 1, 1, 1, 1, 1)
# this is safest!!
some_utc = datetime.datetime(2022, 1, 1, 1, 1, 1, tzinfo=utc_timezone)
ic(some_utc)
timestamp = some_utc.timestamp()
ic(timestamp)
# some_utc_back = datetime.datetime.fromtimestamp(timestamp)
# ic(some_utc_back)
some_utc_back = datetime.datetime.utcfromtimestamp(timestamp)
some_utc_back = utc_timezone.localize(some_utc_back)
ic(some_utc_back)

