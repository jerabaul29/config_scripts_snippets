from pipe import Pipe
from pipe import select as pmap
from pipe import where as filter
from pipe import take

import functools

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

"""
For my part, I like to stick to the usual functional programming terminology:

take
map
filter
reduce
"""


# add a reduce value
@Pipe
def preduce(iterable, function):
    return functools.reduce(function, iterable)


def dummy_func(x):
    print(f"processing at value {x}")
    return x


print("----- test using a range() as input -----")


res_with_range = (range(100) | pmap(dummy_func)
                             | filter(lambda x: x % 2 == 0)
                             | take(2) )

print("*** what is the resulting object ***")
ic(res_with_range)

print("*** what happens when we force evaluation ***")
ic(list(res_with_range))

"""
This prints:

----- test using a range() as input -----
*** what is the resulting object ***
res_with_range: <generator object take at 0x7f60bd506d60>
*** what happens when we force evaluation ***
processing at value 0
processing at value 1
processing at value 2
processing at value 3
processing at value 4
list(res_with_range): [0, 2]
"""

print()
print("----- test using a range() as input but outputing a value not iterator -----")

res_with_reduce = (range(100) | pmap(dummy_func)
                              | filter(lambda x: x % 3 == 1)
                              | take(2)
                              | preduce(lambda x, y: x + y))

ic(res_with_reduce)
