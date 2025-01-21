# %%

import numpy as np
import scipy as sp
import matplotlib.pyplot as plt

# %%

def plot_hist_mismatch(predictor, target, label_base="", bins=30, color=None):
    mismatch = target - predictor
    mismatch_mean = np.mean(mismatch)
    mismatch_std = np.std(mismatch)
    mismatch_skew = sp.stats.skew(mismatch)
    mean_linewidth = 2
    if color is None:
        plt.hist(mismatch, bins=bins, label=label_base + f" err: mean: {mismatch_mean:.2f}; std: {mismatch_std:.2f}; skew: {mismatch_skew:.2f}", histtype=u'step')
        plt.axvline(mismatch_mean, linewidth=mean_linewidth)
    else:
        plt.hist(mismatch, bins=bins, label=label_base + f" err: mean: {mismatch_mean:.2f}; std: {mismatch_std:.2f}; skew: {mismatch_skew:.2f}", histtype=u'step', color=color)
        plt.axvline(mismatch_mean, color=color, linewidth=mean_linewidth)

    plt.xlabel("mismatch")
    plt.ylabel("count")


# %%

x1 = np.random.normal(size=1000)
y1 = 1.1 * np.random.normal(size=1000)

x2 = np.random.normal(size=1000)
y2 = 4.3 + 0.5 * np.random.normal(size=1000)

plt.figure()
plot_hist_mismatch(x1, y1, label_base="ex1", color="k")
plot_hist_mismatch(x2, y2, label_base="ex2", color="r")
plt.legend(loc="lower left",  framealpha=0.99)
plt.show()

# %%

