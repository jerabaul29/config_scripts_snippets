from dataclasses import dataclass
import datetime


@dataclass
class Some_Class:
    some_int: int
    some_float: float
    some_datetime: datetime.datetime


some_class_instance = Some_Class(
        some_int = 1,
        some_float = 3.14,
        some_datetime = datetime.datetime.fromtimestamp(42)
    )
    
print(some_class_instance)
