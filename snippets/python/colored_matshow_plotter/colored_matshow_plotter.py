"""Cross plot a 2D matrix"""

import numpy as np
from numpy import format_float_scientific

import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable

from icecream import ic

ic.configureOutput(outputFunction=print, prefix="")


def matrix_2d_cross_plotter(matrix_to_plot_ij, x_label, y_label, xtickslabels, yticklabels, cbarlabel):
    """Convention is: write your matrix as you expect it to be plotted: will be plotted as you would
    write the np array, i.e.:
        [
            [1, 2],
            [3, 4]
        ]
    """
    assert isinstance(matrix_to_plot_ij, np.ndarray)
    assert len(matrix_to_plot_ij.shape) == 2

    fig, ax = plt.subplots()
    im = ax.matshow(matrix_to_plot_ij, cmap=plt.cm.Blues)

    for i in range(matrix_to_plot_ij.shape[1]):
        for j in range(matrix_to_plot_ij.shape[0]):
            crrt_value = matrix_to_plot_ij[j, i]
            # ax.text(i, j, format_float_scientific(crrt_value, precision=1), va="center", ha="center")
            ax.text(i, j, format_float_scientific(crrt_value, precision=0), va="center", ha="center")

    ax.set_xticks(np.array(list(range(len(xtickslabels)+1)))-1.)
    ax.set_yticks(np.array(list(range(len(yticklabels)+1)))-1.)
    ax.set_xticklabels([''] + xtickslabels)
    ax.set_yticklabels([''] + yticklabels)

    # divider = make_axes_locatable(ax)
    # cax = divider.append_axes('right', size='5%', pad=0.05)
    # fig.colorbar(im, cax=cax, orientation='vertical')
    cbar = fig.colorbar(im, orientation='vertical')
    cbar.set_label(cbarlabel, rotation=270)

    plt.xlabel(x_label)
    plt.ylabel(y_label)


if __name__ == "__main__":
    np_2d = np.array(
        [
            [1, 2],
            [3, 4]
        ]
    )

    # i.e. [1 2] is the xticks corresponding to the outer index: mat[][index_1_2]
    matrix_2d_cross_plotter(np_2d, "xlabel", "ylabel", ['1', '2'], ['a', 'b'], "cbarlabel")
    plt.show()

