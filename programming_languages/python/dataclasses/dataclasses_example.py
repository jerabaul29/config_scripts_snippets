from dataclasses import dataclass
from typing import ClassVar

import datetime


@dataclass
class Some_Class:
    some_const: ClassVar[int] = 20
    some_int: int
    some_float: float
    some_datetime: datetime.datetime
    some_use_of_const: int


some_class_instance = Some_Class(
        some_int = 1,
        some_float = 3.14,
        some_datetime = datetime.datetime.fromtimestamp(42),
        some_use_of_const = Some_Class.some_const * 4
    )

print(some_class_instance)
