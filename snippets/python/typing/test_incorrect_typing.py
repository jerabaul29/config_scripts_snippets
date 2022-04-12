def perform_addition(a: int, b: int) -> int:
    return a + b


res_int = perform_addition(1, 2)
print("got through a full int operation correctly, result: {}".format(res_int))

res_float = perform_addition(1.5, 2.0)
print("got through a float operation while this is an int typed function, result: {}".format(res_float))
print("i.e., typing is only an annotation, this does get executed!")
print("at present, my linter does not even catch anything")
