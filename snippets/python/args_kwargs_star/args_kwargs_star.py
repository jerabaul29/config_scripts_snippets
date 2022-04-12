from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

# ----------------------------------------
# * unpacking an iterable for example a list

fruits = ['lemon', 'pear', 'tomato']
ic(fruits)  # ic the list
ic(*fruits)  # ic the unpack of the list; due to ic, only print first param
print(*fruits)  # print the unpack of the list; will be all terms

numbers = [1, 2, 3]
print(*fruits, *numbers)

list_and_numbers = [*fruits, *numbers]
ic(list_and_numbers)

# ----------------------------------------
# pack arguments given to a function


def some_func_args(*args_to_pack):
    ic(type(args_to_pack))
    ic(args_to_pack)


some_func_args(1, 2, 3)
some_func_args(5, 6)


def some_func_kwargs(**kwargs_to_pack):
    ic(type(kwargs_to_pack))
    ic(kwargs_to_pack)


some_func_kwargs(a=1, b=2)
some_func_kwargs(a=7, b=9, c=5)


def some_func_args_kwargs(int_1, int_2=3, *args, **kwargs):
    ic(args)
    ic(kwargs)


some_func_args_kwargs(1, 2, 3, 4, 5, a=1, b=2, c=3)

# ----------------------------------------
# on the lelft side unpacking

fruits = ["lemon", "pear", "watermelon", "tomato"]

first, second, *remaining = fruits
ic(first)
ic(second)
ic(remaining)

first, *middle, last = fruits
ic(first)
ic(middle)
ic(last)

# ---------------------------------------- 
# list and dict literals

list_1 = [1, 2]
list_2 = [3, 4]
concat = [*list_1, *list_2]
ic(concat)

dict_1 = {'a':1, 'b':2}
dict_2 = {'c':3, 'd':4}
concat = {**dict_1, **dict_2}
# concat = {*dict_1, *dict_2}  # careful not to make this misktake... works, but not what you expect: only keys, and jumbled
ic(concat)
