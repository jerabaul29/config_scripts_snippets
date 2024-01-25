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

# even finer, with formatting :)
some_float = 12.456789
f_str_way_format = f"some_int has value {some_float:{4}.{2}}"
# f_str_way_format = f"some_int has value {some_float}"
print(f_str_way_format)

# even better for "debug" uses: show the variable name
f_str_debug_way = f"{some_int = }"
print(f_str_debug_way)
