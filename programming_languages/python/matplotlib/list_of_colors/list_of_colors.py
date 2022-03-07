import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

import numpy as np

from icecream import ic

ic.configureOutput(prefix="", outputFunction=print)

# ------------------------------------------------------------------------------------------
print("***** configure matplotlib")
plt.rcParams.update({'font.size': 14})
list_colors = list(mcolors.TABLEAU_COLORS)
list_colors.append("k")
list_colors.append("w")
ic(list_colors)

# ------------------------------------------------------------------------------------------
len_list_colors = len(list_colors)
ic(len_list_colors)

list_point_coords = list(range(len_list_colors))
list_0s = np.zeros((len(list_colors, )))

plt.figure()

plt.scatter(list_point_coords, list_0s, color=list_colors)

plt.show()
