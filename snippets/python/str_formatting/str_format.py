some_int = 42

# ugly
old_way = "some_int has value " + str(some_int)
print(old_way)

# quite ok
format_way = "some_int has value {}".format(some_int)
print(format_way)

# even finer :)
f_str_way = f"some_int has value {some_int}"
print(f_str_way)

# even better for "debug" uses: show the variable name
f_str_debug_way = f"{some_int = }"
print(f_str_debug_way)
