import scipy.io
from pathlib import Path

crrt_path = Path("some_path")
crrt_file = crrt_path / "filename.mat"

mat_data = scipy.io.loadmat(crrt_file)

some_field_as_np = mat_data["field_name"].squeeze()

