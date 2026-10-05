#!/usr/bin/env python
# coding: utf-8

# # Convert EarthCARE lightning datasets from NetCDF to Parquet
# This notebook reads NetCDF files from the EarthCARE lightning datasets, and converts them into Parquet format for efficient storage and access. 
# - Monthly files are created for the EarthCARE-frame lightning collection, separately for the GLM and LI instruments. 
# - For along-track lightning counts, one parquet file is created for GLM and one for LI. 
# - For the lightning storm catalogue, two parquet files are produced: one containing cluster summaries and one containing the time evolution of lightning clusters.


import glob
import xarray as xr
import geopandas as gpd
import os
import re
from collections import defaultdict
import pandas as pd
import numpy as np
from pathlib import Path
import gc
import json
from datetime import timedelta
import click


def yield_files_by_month(file_list, date_pattern):

    # Dictionary to hold the groups: Key = (2024, 8), Value = [file1, file2...]
    grouped_files = defaultdict(list)

    for file_path in file_list:
        filename = os.path.basename(file_path)
        match = date_pattern.search(filename)

        if match:
            year = int(match.group(1))
            month = int(match.group(2))
            grouped_files[(year, month)].append(file_path)
        else:
            print(f"Warning: Could not parse date from {filename}")

    for (year, month), files in grouped_files.items():
        yield (year, month), files


def convert_nc_to_parquet(file_list, columns):
    """
    Reads a list of EarthCARE NC files, converts them to a GeoDataFrame,
    sorts by time and location, and saves as GeoParquet.
    """
    dataframes = []

    print(f"Processing {len(file_list)} files...")

    for file_path in file_list:
        try:
            # Open the NetCDF file
            with xr.open_dataset(file_path, decode_timedelta=True) as ds:

                # Convert to Pandas DataFrame
                subset = ds[columns]
                df = subset.to_dataframe().reset_index(drop=True)

                # Extract EarthCARE ID
                path_obj = Path(file_path)
                earthcare_id = path_obj.stem.split('_')[-1]                
                df['earthcare_id'] = earthcare_id

                # add to list
                dataframes.append(df)

        except Exception as e:
            print(f"Error processing file {file_path}: {e}")


    print("Concatenating data...")
    full_df = pd.concat(dataframes, ignore_index=True)

    del dataframes
    gc.collect()


    print("Converting to GeoDataFrame...")
    # Create the geometry column from coordinates
    geometry = gpd.points_from_xy(full_df['longitude'], full_df['latitude'])
    gdf = gpd.GeoDataFrame(full_df, geometry=geometry, crs="EPSG:4326")

    del full_df
    gc.collect()

    print("Sorting data...")
    gdf.sort_values(
        by=['geometry', 'group_time'], 
        inplace=True, 
        ignore_index=True
    )

    return gdf


def process_col2_nc_to_geoparquet(file_list):
    """
    Reads EarthCARE NC files, expands 2D variables (cpr, subcluster_id) 
    into a flat dataframe, sorts, and saves as GeoParquet.
    """
    dataframes = []

    for file_path in file_list:
        try:
            with xr.open_dataset(file_path) as ds:

                df = ds.to_dataframe().reset_index()
                path_obj = Path(file_path)
                earthcare_id = path_obj.stem.split('_')[-1]
                df['earthcare_id'] = earthcare_id
                dataframes.append(df)

        except Exception as e:
            print(f"Skipping {file_path}: {e}")


    print("Concatenating all files...")
    full_df = pd.concat(dataframes, ignore_index=True)

    del dataframes
    gc.collect()

    print("Creating GeoDataFrame...")
    geometry = gpd.points_from_xy(full_df['longitude'], full_df['latitude'])
    full_df.drop(columns=['latitude', 'longitude', 'cpr'], inplace=True)
    gdf = gpd.GeoDataFrame(full_df, geometry=geometry, crs="EPSG:4326")

    del full_df
    gc.collect()

    print("Sorting data...")
    gdf.sort_values(
        by=['geometry', 'time'], 
        inplace=True, 
        ignore_index=True
    )

    return gdf


def transform_json_to_parquet(json_file_path):

    with open(json_file_path, 'r') as f:
        content = json.load(f)

    data = content['data']

    df_summary = pd.DataFrame(data if data else {key: [] for key in content['metadata']}).drop(
        columns=['minute_counts', 'minute_mean_lat', 'minute_mean_lon', 'masked_minute_counts'], errors='ignore'
    )

    # Convert types
    df_summary['peak_datetime'] = pd.to_datetime(df_summary['peak_datetime'], format='mixed')
    gdf_summary = gpd.GeoDataFrame(
        df_summary,
        geometry=gpd.points_from_xy(df_summary['peak_lon'], df_summary['peak_lat']),
        crs="EPSG:4326"
    )

    # the Evolution GeoDataFrame (Detail) ---
    evolution_rows = []

    for entry in data:
        common_ids = {
            'unique_id': entry['unique_id'],
            'peak_datetime': pd.to_datetime(entry['peak_datetime'])
        }

        minutes = entry['minute_counts'].keys()

        for m_str in minutes:
            minute_offset = int(m_str)
            abs_time = common_ids['peak_datetime'] + timedelta(minutes=minute_offset)

            row = common_ids.copy()
            row['minute_offset'] = minute_offset
            row['absolute_time'] = abs_time
            row['lightning_count'] = entry['minute_counts'][m_str]
            row['masked_lightning_count'] = entry.get('masked_minute_counts', {}).get(m_str)
            row['latitude'] = entry['minute_mean_lat'][m_str]
            row['longitude'] = entry['minute_mean_lon'][m_str]

            evolution_rows.append(row)

    df_evolution = pd.DataFrame(evolution_rows, columns=[
        'unique_id', 'peak_datetime', 'minute_offset', 'absolute_time',
        'lightning_count', 'masked_lightning_count', 'latitude', 'longitude'
    ])

    # Create Geometry (Track Location)
    gdf_evolution = gpd.GeoDataFrame(
        df_evolution,
        geometry=gpd.points_from_xy(df_evolution['longitude'], df_evolution['latitude']),
        crs="EPSG:4326"
    )

    gdf_evolution = gdf_evolution.sort_values(by=['unique_id', 'absolute_time',])

    return gdf_summary, gdf_evolution


@click.command()
@click.option('--catalogue', 'json_file_path', required=True,
              type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option('--source-dir', type=click.Path(exists=True, file_okay=False, path_type=Path),
              help='Optional collocation output directory for NetCDF conversion.')
@click.option('--output-dir', default='parquet', show_default=True,
              type=click.Path(file_okay=False, path_type=Path))
def main(json_file_path, source_dir, output_dir):
    """Convert catalogue JSON, and optionally lightning_groups/track_counts, to Parquet."""
    output_dir.mkdir(parents=True, exist_ok=True)
    if source_dir is not None:
        (output_dir / 'lightning_groups_parquet').mkdir(exist_ok=True)
        (output_dir / 'track_counts_parquet').mkdir(exist_ok=True)
    output_dir = str(output_dir) + os.sep

    if source_dir is not None:
        files = sorted(glob.glob(str(source_dir / 'lightning_groups' / '*.nc')))
        files2 = sorted(glob.glob(str(source_dir / 'track_counts' / '*.nc')))
        # ### Collection 1
        #
        # Convert and store the GLM files

        parquet_dir = output_dir + 'lightning_groups_parquet/'
        source = 'GLM'
        date_pattern = re.compile(r"GLM_(\d{4})(\d{2})")
        source_files = [f for f in files if source in f]
        columns = ['group_id',
         'group_time',
         'latitude',
         'longitude',
         'radiance',
         'flash_id',
         'ec_time_diff',
         'parent_cluster_id',
         'cluster_id',
         'distance_from_nadir']
        earthcare_ids = {}
        for ((year, month), filelist) in yield_files_by_month(source_files, date_pattern):
            gdf = convert_nc_to_parquet(filelist, columns)
            gdf['source'] = source
            gdf.to_parquet(
                parquet_dir + f'EC_lightning_{source}_{year}_{month}.parquet',
                engine='pyarrow',
                compression='zstd',
                write_covering_bbox=True,
                schema_version='1.1.0'
            )
            for id in gdf['earthcare_id'].unique():
                earthcare_ids.setdefault(id, []).append(f'EC_lightning_{source}_{year}_{month}.parquet')

        # Convert and store the LI files

        parquet_dir = output_dir + 'lightning_groups_parquet/'
        source = 'LI'
        date_pattern = re.compile(r"LI_(\d{4})(\d{2})")
        source_files = [f for f in files if source in f]
        columns = ['group_id',
         'group_time',
         'latitude',
         'longitude',
         'radiance',
         'flash_id',
         'parallax_corrected_lat',
         'parallax_corrected_lon',
         'ec_time_diff',
         'parent_cluster_id',
         'cluster_id',
         'distance_from_nadir']
        for ((year, month), filelist) in yield_files_by_month(source_files, date_pattern):
            gdf = convert_nc_to_parquet(filelist,columns)
            gdf['source'] = source
            gdf.to_parquet(
                parquet_dir + f'EC_lightning_{source}_{year}_{month}.parquet',
                engine='pyarrow',
                compression='zstd',
                write_covering_bbox=True,
                schema_version='1.1.0'
            )
            for id in gdf['earthcare_id'].unique():
                earthcare_ids.setdefault(id, []).append(f'EC_lightning_{source}_{year}_{month}.parquet')

        # Write the earthcare-id -> file dictionary as a parquet file.

        df = pd.Series(earthcare_ids).reset_index()
        df.columns = ['earthcare_id', 'files']
        df.to_parquet(output_dir + 'earthcare_id_mapping.parquet', engine='pyarrow', compression='zstd')

        # ### Collection 2

        # Process LI files in one go.

        parquet_dir = output_dir + 'track_counts_parquet/'
        source = 'LI'
        source_files = [f for f in files2 if source in f]
        if source_files:
            gdf = process_col2_nc_to_geoparquet(source_files)
            gdf['source'] = source
            gdf.to_parquet(
                parquet_dir + f'EC_track_lightning_{source}.parquet',
                engine='pyarrow',
                compression='zstd',
                write_covering_bbox=True,
                schema_version='1.1.0'
            )

        # Process GLM files in one go.

        parquet_dir = output_dir + 'track_counts_parquet/'
        source = 'GLM'
        source_files = [f for f in files2 if source in f]
        if source_files:
            gdf = process_col2_nc_to_geoparquet(source_files)
            gdf['source'] = source
            gdf.to_parquet(
                parquet_dir + f'EC_track_lightning_{source}.parquet',
                engine='pyarrow',
                compression='zstd',
                write_covering_bbox=True,
                schema_version='1.1.0'
            )

    # ### Collection 3
    #
    # Process the collection 3 files.

    gdf_summary, gdf_evolution = transform_json_to_parquet(json_file_path)
    gdf_summary.to_parquet(output_dir + 'EC_lightning_clusters.parquet', index=False)
    gdf_evolution.to_parquet(output_dir + 'EC_lightning_cluster_evolution.parquet', index=False)

    # Tests and Asserts: compare a randomly selected NetCDF with its Parquet output.
    if source_dir is not None and files:
        def extract_file_info(file_path):
            filename = os.path.basename(file_path)
            parts = filename.split('_')
            source = parts[0]
            date_str = parts[1]
            year = int(date_str[:4])
            month = int(date_str[4:6])
            return source, year, month

        np.random.seed(42)
        rf = np.random.choice(files)
        t, y, m = extract_file_info(rf)
        new = gpd.read_parquet(
            output_dir + f'lightning_groups_parquet/EC_lightning_{t}_{y}_{m}.parquet'
        )
        new = new[new['earthcare_id'] == Path(rf).stem.split('_')[-1]]

        with xr.open_dataset(rf, decode_timedelta=True) as orig:
            for d in orig.data_vars:
                assert orig[d].dropna(dim='groups').isin(new[d].values).all().values, d

            subset = new[new.group_id.isin(orig['group_id'].values) & new.group_time.isin(orig['group_time'].values)]
            subset = subset.sort_values(by='group_id').reset_index(drop=True)
            orig = orig.sortby('group_id')
            assert len(subset) == orig.sizes['groups'], 'Group count differs'

            columns_to_check = ['group_id', 'latitude', 'longitude', 'radiance', 'flash_id',
                                'parent_cluster_id', 'cluster_id', 'distance_from_nadir']
            for c in columns_to_check:
                assert np.isclose(subset[c], orig[c].values, equal_nan=True).all(), c
        print(f'Checks passed for {Path(rf).name}')


if __name__ == '__main__':
    main()
