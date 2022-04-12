from dataclasses import dataclass
from typing import ClassVar

import datetime


@dataclass
class Some_Class:
    some_const: ClassVar[int] = 20
    some_int: int
    some_float: float
    some_float_less_than_3: float
    some_datetime: datetime.datetime
    some_use_of_const: int

    def __post_init__(self):
        """our class consistency checks to be performed after initialization."""
        # this risks to not be executed in release mode...
        # assert self.some_float_less_than_3 < 3, f"got {self.some_float_less_than_3} for some_float_less_than_3"
        if self.some_float_less_than_3 > 3:
            raise RuntimeError(f"got {self.some_float_less_than_3} for some_float_less_than_3"
)


some_class_instance = Some_Class(
        some_int = 1,
        some_float = 3.14,
        some_float_less_than_3 = 2.4,
        some_datetime = datetime.datetime.fromtimestamp(42),
        some_use_of_const = Some_Class.some_const * 4
    )

print(some_class_instance)

some_class_instance_erroneous = Some_Class(
        some_int = 1,
        some_float = 3.14,
        some_float_less_than_3 = 3.4,
        some_datetime = datetime.datetime.fromtimestamp(42)
    )

print(some_class_instance_erroneous)
