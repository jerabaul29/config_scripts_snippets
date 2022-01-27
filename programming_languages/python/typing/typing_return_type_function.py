from typing import Callable
import datetime

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)


def func_that_return_func(some_int: int) -> Callable[[float, datetime.datetime], int]:
    def some_func(some_float: float, some_datetime: datetime.datetime) -> int:
        return int(some_float) + some_datetime.second + some_int

    return some_func


some_func = ic(func_that_return_func(10))
ic(some_func(100.0, datetime.datetime(2020, 1, 1, 1, 1, 1)))

