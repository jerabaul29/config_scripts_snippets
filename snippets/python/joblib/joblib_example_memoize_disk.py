from pathlib import Path
from joblib import Memory

memory = Memory(location=Path.cwd(), verbose=0, compress=True)


@memory.cache
def some_func(a, b):
    return a + b


some_func(3, 4)
some_func(3, 4)
some_func(5, 4)
