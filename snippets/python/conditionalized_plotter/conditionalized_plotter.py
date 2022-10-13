import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

import numpy as np
from icecream import ic
from numpy import isin

from mo_sv_data.utils.binning import bin_data

ic.configureOutput(prefix="", outputFunction=print)

plt.rcParams.update({'font.size': 14})
list_colors = list(mcolors.TABLEAU_COLORS)
list_colors.append("k")
list_colors.append("w")

# show one variable, conditionalized by another
# useful for example for plotting the error, conditionalized by different input variables


def show_conditionalized_variable(variable_to_show, conditionalization_variable, variable_to_show_stringname, conditionalization_stringname, list_nbr_bins, min_nbr_entries_per_bin=25):
    """
    variable_to_show: what variable we are looking at
    conditionalization_variable: what variable is binned and used as a "predictor"
    title: plot title for saving
    list_nbr_bins: list of nbr of bins to use for binning
    """

    assert isinstance(variable_to_show, np.ndarray), "need numpy input"
    assert isinstance(conditionalization_variable, np.ndarray), "need numpy input"
    assert len(np.shape(variable_to_show)) == 1, "only works for 1D input arrays"
    assert len(np.shape(conditionalization_variable)) == 1, "only works for 1D input arrays"
    assert variable_to_show.shape == conditionalization_variable.shape, "both variables need to have the same size"

    list_colors_mean = ["k", "b", "magenta"]
    list_colors_std = ["r", "orange", "yellow"]

    fig, axes = plt.subplots(nrows=2, ncols=2, figsize=(19, 12))

    mean_variable_to_show = np.mean(variable_to_show)
    std_variable_to_show = np.std(variable_to_show)

    for bin_nbr_index, nbr_bins in enumerate(list_nbr_bins):
        dict_data_per_bin = {}  # binning by the conditionalization variable
        dict_data_per_bin_toshow = {}  # binning by the variable to show itself

        for crrt_bin_nbr in range(nbr_bins):
            dict_data_per_bin[crrt_bin_nbr] = []
            dict_data_per_bin_toshow[crrt_bin_nbr] = []

        _, bin_mids, array_bin_indexes = bin_data(conditionalization_variable, nbr_bins)
        _, bin_mids_toshow, array_bin_indexes_toshow = bin_data(variable_to_show, nbr_bins)

        for crrt_bin, crrt_variable_value in zip(array_bin_indexes, variable_to_show):
            dict_data_per_bin[crrt_bin].append(crrt_variable_value)

        for crrt_bin, crrt_variable_value in zip(array_bin_indexes_toshow, variable_to_show):
            dict_data_per_bin_toshow[crrt_bin].append(crrt_variable_value)

        for crrt_bin in range(nbr_bins):
            if len(dict_data_per_bin[crrt_bin]) < min_nbr_entries_per_bin:
                dict_data_per_bin[crrt_bin] = []
            if len(dict_data_per_bin_toshow[crrt_bin]) < min_nbr_entries_per_bin:
                dict_data_per_bin_toshow[crrt_bin] = []

        # show

        mean_error_per_bin = np.array([np.mean(dict_data_per_bin[crrt_bin]) for crrt_bin in range(nbr_bins)])
        std_error_per_bin = np.array([np.std(dict_data_per_bin[crrt_bin]) for crrt_bin in range(nbr_bins)])
        density_samples_per_bin = np.array([len(dict_data_per_bin[crrt_bin]) for crrt_bin in range(nbr_bins)]) / (bin_mids[1] - bin_mids[0])
        density_samples_per_bin = density_samples_per_bin / np.max(density_samples_per_bin)

        density_samples_per_bin_toshow = np.array([len(dict_data_per_bin_toshow[crrt_bin]) for crrt_bin in range(nbr_bins)]) / (bin_mids_toshow[1]-bin_mids_toshow[0])
        density_samples_per_bin_toshow = density_samples_per_bin_toshow / np.max(density_samples_per_bin_toshow)

        axes[0, 0].plot(density_samples_per_bin_toshow, bin_mids_toshow, color=list_colors_mean[bin_nbr_index], label=f"{nbr_bins} bins", marker="*")

        axes[0, 1].plot(bin_mids, mean_error_per_bin, color=list_colors_mean[bin_nbr_index], linewidth=3, label=f"mean error {nbr_bins} bins", marker="*")
        axes[0, 1].plot(bin_mids, mean_error_per_bin+std_error_per_bin, color=list_colors_std[bin_nbr_index], linewidth=1, label=f"1 std {nbr_bins} bins")
        axes[0, 1].plot(bin_mids, mean_error_per_bin-std_error_per_bin, color=list_colors_std[bin_nbr_index], linewidth=1)

        axes[1, 1].plot(bin_mids, density_samples_per_bin, color=list_colors_mean[bin_nbr_index], label=f"{nbr_bins} bins", marker="*")

    axes[0, 0].set_ylabel(variable_to_show_stringname)
    axes[0, 0].set_xlabel("rel density of samples")
    lims_axes1 = axes[0, 1].get_ylim()
    axes[0, 0].set_ylim(lims_axes1)
    axes[0, 0].axhline(np.mean(variable_to_show), linewidth=3, label="mean", linestyle="--", color="k")
    axes[0, 0].axhline(np.mean(variable_to_show)-np.std(variable_to_show), linewidth=3, label="mean +- 1std", color="r", linestyle="--")
    axes[0, 0].axhline(np.mean(variable_to_show)+np.std(variable_to_show), linewidth=3, color="r", linestyle="--")

    axes[0, 1].axhline(mean_variable_to_show, color="k", linewidth=5, label="mean", linestyle="--")
    axes[0, 1].axhline(mean_variable_to_show-std_variable_to_show, color="r", linewidth=5, label="mean +- 1std", linestyle="--")
    axes[0, 1].axhline(mean_variable_to_show+std_variable_to_show, color="r", linewidth=5, linestyle="--")
    axes[0, 1].axvline(np.mean(conditionalization_variable), linewidth=5, linestyle="--", color="k")
    axes[0, 1].axvline(np.mean(conditionalization_variable)-np.std(conditionalization_variable), linewidth=5, color="r", linestyle="--")
    axes[0, 1].axvline(np.mean(conditionalization_variable)+np.std(conditionalization_variable), linewidth=5, color="r", linestyle="--")

    axes[1, 1].set_xlabel(conditionalization_stringname)
    axes[1, 1].set_ylabel("rel density of samples")
    lims_axes1 = axes[0, 1].get_xlim()
    axes[1, 1].set_xlim(lims_axes1)
    axes[1, 1].axvline(np.mean(conditionalization_variable), linewidth=3, label="mean", linestyle="--", color="k")
    axes[1, 1].axvline(np.mean(conditionalization_variable)-np.std(conditionalization_variable), linewidth=3, label="mean +- 1std", color="r", linestyle="--")
    axes[1, 1].axvline(np.mean(conditionalization_variable)+np.std(conditionalization_variable), linewidth=3, color="r", linestyle="--")

    axes[1, 0].remove()

    axes[0, 0].legend()
    axes[0, 1].legend(ncol=len(list_nbr_bins)+1)
    axes[1, 1].legend()

    fig.tight_layout()
    fig.savefig(f"figs/condplot_{variable_to_show_stringname}_conditionalizedby_{conditionalization_stringname}.png")


if __name__ == "__main__":
    import time
    import os

    print("***** Put the interpreter in UTC, to make sure no TZ issues")
    os.environ["TZ"] = "UTC"
    time.tzset()

    import datetime

    from mo_sv_data.load_data.load_all_turblev1_data import *

    import pytz

    print("NOTE: the example will only work on a computer with the MO Uppsala in situ data")
    # TODO: fixme: generate a dummy example that works anyways

    utc_timezone = pytz.timezone("UTC")
    # reduced time span, to generate figures faster when "just" doing some testing

    datetime_start = datetime.datetime(1995, 1, 1, 0, 15, 0, tzinfo=utc_timezone)
    datetime_end = datetime.datetime(2021, 1, 1, 0, 15, 0, tzinfo=utc_timezone)

    crrt_instrument_kind = 3
    crrt_segment_windfrom = 3

    crrt_admissible_indexes = np.logical_and.reduce(
        (
            datetime_start < common_time_base,
            common_time_base < datetime_end,
            instrument_kind == crrt_instrument_kind,
            np_segments_windfrom == crrt_segment_windfrom,
            np.isfinite(alongwind_stress),
            np.isfinite(wind_stress),
            np.isfinite(buoyancy_flux),
        )
    )

    variable_to_show = (alongwind_stress - wind_stress)[crrt_admissible_indexes]
    variable_to_show_stringname = "error dcm - coare35"

    conditionalization_stringname = "windspeed"
    conditionalization_variable = globals()[conditionalization_stringname][crrt_admissible_indexes]

    list_nbr_bins = [60, 120]

    show_conditionalized_variable(variable_to_show, conditionalization_variable, variable_to_show_stringname, conditionalization_stringname, list_nbr_bins)
    plt.show()
