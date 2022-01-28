from pathlib import Path

from typing import Callable

import pickle as pkl
import compress_pickle as cpkl

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

some_object = [1, (2, 3), "bla"]
ic(some_object)

# ----------------------------------------

path_pkl = Path.cwd() / "pkl_dump.pkl"

# dump with pickle
with open(path_pkl, "bw") as fh:
    pkl.dump(some_object, fh)

# load with pickle
with open(path_pkl, "br") as fh:
    some_object_loaded = pkl.load(fh)
ic(some_object_loaded)

# ----------------------------------------

path_cpkl = Path.cwd() / "cpkl_dump.cpkl"

# dump with compress pickle
with open(path_cpkl, "bw") as fh:
    cpkl.dump(some_object, fh, compression="lzma", set_default_extension=False)

# load with compress pickle
with open(path_cpkl, "br") as fh:
    some_object_re_loaded = cpkl.load(fh, compression="lzma")

ic(some_object_re_loaded)

# ----------------------------------------

# a common pattern is to load if on disk, generate if not on disk


def load_or_generate(path_to_dump: Path, object_factory: Callable, *factory_args, **factory_kwargs) -> object:
    if not path_to_dump.suffix == ".cpkl":
        raise RuntimeError("we load or generate from a .cpkl path")

    if path_to_dump.is_file():
        print("we load")
        with open(path_to_dump, "br") as fh:
            object_to_retrieve = cpkl.load(fh, compression="lzma")
            return object_to_retrieve
    else:
        print("we generate")
        object_to_retrieve = object_factory(*factory_args, **factory_kwargs)
        with open(path_to_dump, "bw") as fh:
            cpkl.dump(object_to_retrieve, fh, compression="lzma", set_default_extension=False)
        return object_to_retrieve


def example_factory(int_1, int_2):
    return [int_1, int_2]


path_to_object_dump = Path.cwd() / "object_dump.cpkl"

object_to_retrieve = load_or_generate(path_to_object_dump, example_factory, 1, int_2=3)
ic(object_to_retrieve)