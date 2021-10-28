import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib import cm


class ColormapMapper:
    """A mapper from values to RGB colors using built in colormaps
    and scaling these."""

    def __init__(self, cmap, vmin, vmax, warn_saturated=False):
        """cmap: the matplotlib colormap to use, min: the min value to be plotted,
        max: the max value to be plotted."""
        self.vmin = vmin
        self.vmax = vmax
        self.warn_saturated = warn_saturated
        norm = mpl.colors.Normalize(vmin=vmin, vmax=vmax)
        self.normalized_colormap = cm.ScalarMappable(norm=norm, cmap=cmap)

    def get_rgb(self, val):
        """Get the RGB value associated with val given the normalized colormap
        settings."""
        if self.warn_saturated:
            if val < self.vmin:
                print("ColormapHelper warning: saturated low value")
            if val > self.vmax:
                print("ColormapHelper warning: saturated high value")

        return self.normalized_colormap.to_rgba(val)


if __name__ == "__main__":
    import numpy as np

    arange = np.arange(0, 1, 0.05)
    all_zeros = np.zeros(arange.shape)
    colormap_mapper = ColormapMapper(plt.get_cmap("viridis"), 0, 1)
    colors = np.transpose(np.vectorize(colormap_mapper.get_rgb)(arange))

    plt.figure()
    plt.scatter(x=arange, y=all_zeros, s=300, c=colors)
    plt.show()
