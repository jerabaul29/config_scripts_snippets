# %%

exit()

# %%

# ipython3 --pdb
ipython3

# %%

import numpy as np
import matplotlib.pyplot as plt
import scipy as sp

# %%


def scatter_with_trend(x: np.ndarray, y: np.ndarray):
    data , x_e, y_e = np.histogram2d( x, y, bins=20, density=True )
    z = sp.interpolate.interpn( ( 0.5*(x_e[1:] + x_e[:-1]) , 0.5*(y_e[1:]+y_e[:-1]) ) , data , np.vstack([x,y]).T , method = "splinef2d", bounds_error = False)
    z[np.where(np.isnan(z))] = 0.0

    # Sort the points by density, so that the densest points are plotted last
    if True:
        idx = z.argsort()
        x, y, z = x[idx], y[idx], z[idx]

    plt.scatter(x, y, c=z)

    # the trend on it:
    #
    # with linear polyfit (can also allow for higher order)
    # order = 1
    # coeffs = np.polyfit(x, y, order)
    # fit = np.poly1d(coeffs)
    #
    # easier with sp.stats for purely linear fit
    slope, intercept, rsquared, p_value, std_err = sp.stats.linregress(x, y)

    def fit(x):
        return slope * x + intercept
    
    
    minx = np.min(x)
    maxx = np.max(x)

    rsquared = float(rsquared)

    plt.plot([minx, maxx], [fit(minx), fit(maxx)], color="red", linewidth=3, label=f"R-squared: {rsquared:.2f} | slope: {slope:.2f}")


# %%

# example of use

# Generate fake data
x = np.random.normal(size=1000)
y = x * 3 + np.random.normal(size=1000)

plt.figure()

scatter_with_trend(x, y)
plt.legend()
plt.xlabel("x")
plt.ylabel("y")

plt.show()

# %%
