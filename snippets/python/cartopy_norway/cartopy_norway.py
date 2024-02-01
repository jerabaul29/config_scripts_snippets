# %%

%reset -f

# %%

import xarray as xr

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import cartopy.io.shapereader as shpreader
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER

import geopandas as gpd

import numpy as np
import datetime
import pandas as pd

# %%

_ = ccrs.PlateCarree()

# the map projection properties.
proj = ccrs.LambertConformal(central_latitude=65.0,
                             central_longitude=15.0,
                             standard_parallels=(52.5, 75.0))

scaling = 0.6
plt.figure(figsize=(10*scaling, 12*scaling))
ax = plt.axes(projection=proj)

resol = '50m'
bodr = cartopy.feature.NaturalEarthFeature(category='cultural',
                                           name='admin_0_boundary_lines_land',
                                           scale=resol, facecolor='none', alpha=0.7)
land = cartopy.feature.NaturalEarthFeature('physical', 'land',
                                           scale=resol, edgecolor='k', facecolor="grey")
ocean = cartopy.feature.NaturalEarthFeature('physical', 'ocean',
                                            scale=resol, edgecolor='none', facecolor=cfeature.COLORS['water'])
lakes = cartopy.feature.NaturalEarthFeature('physical', 'lakes',
                                            scale=resol, edgecolor='b', facecolor=cfeature.COLORS['water'])
rivers = cartopy.feature.NaturalEarthFeature('physical', 'rivers_lake_centerlines',
                                             scale=resol, edgecolor='b', facecolor='none')

ax.add_feature(ocean, linewidth=0.2, zorder=0)
ax.add_feature(land, zorder=0)

gl = ax.gridlines(crs=ccrs.PlateCarree(), draw_labels=True, x_inline=False,
                  linewidth=2, color='gray', alpha=0.5, linestyle='--')
#
gl.xlines = True
gl.ylines = True
#
gl.xformatter = LONGITUDE_FORMATTER
gl.yformatter = LATITUDE_FORMATTER

shpfilename = shpreader.natural_earth(resolution='50m',
                                      category='cultural',
                                      name='admin_0_countries')
reader = shpreader.Reader(shpfilename)
countries = reader.records()

for country in countries:
    if country.attributes['ADM0_A3'] in ["NOR"]:
        ax.add_geometries(country.geometry, ccrs.PlateCarree(),
                          facecolor="moccasin",
                          alpha=0.95
                          )

ax.add_feature(lakes, zorder=2)
ax.add_feature(rivers, linewidth=0.5, zorder=2)
ax.add_feature(bodr, linestyle='--', linewidth=2.0, edgecolor='k', alpha=0.5, zorder=2)

# files from: https://github.com/robhop/fylker-og-kommuner/tree/main
fylker = gpd.read_file('Fylker-S.geojson')

for crrt_fylke in fylker.iterrows():
    crrt_polygon = crrt_fylke[1]["geometry"]
    ax.add_geometries([crrt_polygon], crs=ccrs.PlateCarree(), edgecolor='black', linewidth=0.1, facecolor="none")

ax.set_extent([2, 26, 57, 72])

plt.tight_layout()

plt.show()

# %%
