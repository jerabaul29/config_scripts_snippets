import numpy as np
import matplotlib.pyplot as plt

nbr_points = 10

cmap = plt.cm.viridis
list_colors = cmap(np.linspace(0, 1, nbr_points))

plt.figure()

for i, crrt_color in zip(range(nbr_points), list_colors):
    plt.scatter([0], [i], color=crrt_color, label=i)

plt.legend()
plt.show()

