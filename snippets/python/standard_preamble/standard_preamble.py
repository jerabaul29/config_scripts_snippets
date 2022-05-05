import time
import os

# ------------------------------------------------------------------------------------------
print("***** Put the interpreter in UTC, to make sure no TZ issues")
os.environ["TZ"] = "UTC"
time.tzset()

from icecream import ic

import pytz

utc_timezone = pytz.timezone("UTC")

ic.configureOutput(prefix="", outputFunction=print)

