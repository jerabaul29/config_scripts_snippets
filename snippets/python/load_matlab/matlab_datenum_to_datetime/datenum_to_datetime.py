import datetime

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)


def matlab_datenum_to_datetime(matlab_datenum: float) -> datetime.datetime:
    day = datetime.datetime.fromordinal(int(matlab_datenum))
    day_fraction = datetime.timedelta(days=matlab_datenum % 1) - datetime.timedelta(days=366)
    return day + day_fraction


# example from https://se.mathworks.com/help/matlab/ref/now.html
matlab_datenum = 738400.460972527
corresponding_datetime = datetime.datetime(2021, 9, 1, 11, 3, 48, 26336)
ic(matlab_datenum)
ic(matlab_datenum_to_datetime(matlab_datenum))
ic(corresponding_datetime)
assert matlab_datenum_to_datetime(matlab_datenum) == corresponding_datetime

# on an array, do:
import numpy as np

vec_mdate_to_datetime = np.vectorize(matlab_datenum_to_datetime)
ic(vec_mdate_to_datetime(np.array([738400.46097252, 738401.46097252])))

