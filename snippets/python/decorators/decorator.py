import functools
from typing import Callable


def do_twice(func: Callable, *args, **kwargs) -> Callable:
    # if we want to preserve information about the original function
    # such as .__name__ and help(), we need the following
    @functools.wraps(func)
    def wrapper_do_twice(*args, **kwargs):
        print("show args")
        for arg in args:
            print(arg)
        for kwarg in kwargs:
            print(f"kwargs[{kwarg}] = {kwargs[kwarg]}")
        print("compute once")
        func(*args, **kwargs)
        print("compute twice and return")
        return_value = func(*args, **kwargs)
        return return_value

    return wrapper_do_twice


@do_twice
def example_func(a, b, c):
    return a + b + c


example_func(1, 2, c=3)
print(example_func.__name__)
