# ---
# method 1: often some issues

import scipy.io
from pathlib import Path

crrt_path = Path("some_path")
crrt_file = crrt_path / "filename.mat"

mat_data = scipy.io.loadmat(crrt_file)

some_field_as_np = mat_data["field_name"].squeeze()

# ---
# method 2: has been working fine for me

from pymatreader import read_mat

data = read_mat("some_path")
# from there, a well behaved dict is available :) 
