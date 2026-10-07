#!/usr/bin/env python
# coding: utf-8

# import libraries
import click
import geopandas as gpd
import numpy as np
import pandas as pd
from pathlib import Path
from pystac import Collection
import pystac
import xarray as xr
from datetime import datetime, timezone
from shapely.geometry import box, mapping, Point, LineString
import shutil


def _variable_metadata(directory, pattern):
    file = next(directory.glob(pattern), None)
    if file is None:
        return {}
    with xr.open_dataset(file) as ds:
        return {
            var: {key: value.tolist() if hasattr(value, 'tolist') else value
                  for key, value in ds[var].attrs.items()}
            for var in ds.variables
        }


def _add_parquet_item(collection, file, parquet_dir, output_dir,
                      time_column, columns, product_type, source=None):
    if not file.exists():
        return
    gdf = gpd.read_parquet(file)
    if gdf.empty:
        return

    # Use the actual geographic extent and observation times in this file.
    gdf = gdf.to_crs('EPSG:4326')
    bounds = list(gdf.total_bounds)  # [minx, miny, maxx, maxy]
    times = pd.to_datetime(gdf[time_column], utc=True).dropna()
    if not np.isfinite(bounds).all() or times.empty:
        raise ValueError(f'No spatial or temporal extent available for {file.name}')
    if bounds[0] == bounds[2] and bounds[1] == bounds[3]:
        geom = mapping(Point(bounds[0], bounds[1]))
    elif bounds[0] == bounds[2] or bounds[1] == bounds[3]:
        geom = mapping(LineString([(bounds[0], bounds[1]), (bounds[2], bounds[3])]))
    else:
        geom = mapping(box(*bounds))
    start_dt = times.min().to_pydatetime(warn=False)
    end_dt = times.max().to_pydatetime(warn=False)

    # Only the storm tables filter column descriptions in the original notebook.
    if source is None:
        columns = {col: columns[col] for col in gdf.columns if col in columns}
    properties = {
        'parquet:columns': columns,
        'type': product_type,
        'start_datetime': start_dt.isoformat().replace('+00:00', 'Z'),
        'end_datetime': end_dt.isoformat().replace('+00:00', 'Z'),
        'created': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    }
    if source is not None:
        properties['source'] = source

    # Create the STAC Item
    item = pystac.Item(
        id=file.stem,
        geometry=geom,
        bbox=bounds,
        datetime=None,
        properties=properties
    )

    # Keep the referenced data inside the output folder so it can be moved as a unit.
    asset_path = output_dir / 'parquet' / file.relative_to(parquet_dir)
    asset_path.parent.mkdir(parents=True, exist_ok=True)
    if file.resolve() != asset_path.resolve():
        shutil.copy2(file, asset_path)

    # add the asset
    asset = pystac.Asset(
        href=str(asset_path.resolve()),
        media_type='application/x-parquet',
        roles=['data']
    )
    item.add_asset(key='data', asset=asset)
    collection.add_item(item)
    print(f'  - Added Item: {item.id}')


@click.command()
@click.option('--parquet-dir', required=True,
              type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.option('--source-dir', type=click.Path(exists=True, file_okay=False, path_type=Path),
              help='Optional collocation output directory for NetCDF variable metadata.')
@click.option('--output-dir', default='stac', show_default=True,
              type=click.Path(file_okay=False, path_type=Path))
def main(parquet_dir, source_dir, output_dir):
    """Create a local STAC catalogue containing the Parquet results."""
    output_dir.mkdir(parents=True, exist_ok=True)
    created = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    catalog = pystac.Catalog(
        id='earthcare-lightning',
        title='EarthCARE lightning results',
        description='EarthCARE-frame lightning, along-track lightning counts and storm catalogue results.'
    )

    # ## Create the EarthCARE-frame lightning collection
    # to which the files/STAC items will be added.

    collectionid = "earthcare-frame-lightning"
    description = "The EarthCARE-frame lightning product provides geostationary satellite-detected lightning groups collocated with individual EarthCARE MSI-like observation frames. It includes all lightning activity occurring within the frame and a surrounding 0.5° bounding box within the configured time window around the EarthCARE overpass. The product is distributed as monthly Parquet files, with MTG-LI and GOES-GLM observations stored separately. The dataset contains lightning groups together with their time, location, radiance, and associated flash identifier. Additional variables describe the temporal difference from the EarthCARE overpass, parallax-corrected lightning positions for groups close to the overpass, and clustering information used to identify lightning structures within storms."
    collection = Collection.from_dict(

    {
      "type": "Collection",
      "id": collectionid,
      "stac_version": "1.1.0",
      "title": "EarthCARE-frame lightning",
      "description": description,
      "extent": {
        "spatial": {
          "bbox": [
            [-180,
             -90,
             180,
             90]
          ]
        },
        "temporal": {
          "interval": [
            [
              None,
              None
            ]
          ]
        }
      },
      "license": "CC-BY-4.0",
      "links": [],
      "created": created,
      "summaries": {
        "platform": [
          "EarthCARE",
          "MTG-I1",
          "GOES-16",
          "GOES-18",
          "GOES-19",
        ],
        "instruments": [
          "MSI",
          "LI",
          "GLM"
        ]
      }

    }

    )

    # Extract all variable metadata from sample nc files.
    li_vars = glm_vars = {}
    if source_dir is not None:
        lightning_path = source_dir / 'lightning_groups'
        glm_vars = _variable_metadata(lightning_path, 'GLM_*.nc')
        li_vars = _variable_metadata(lightning_path, 'LI_*.nc')

    # Generate stac items per file type and add to the collection.
    parquet_path = parquet_dir / 'lightning_groups_parquet'
    c1_li_files = sorted(parquet_path.glob('EC_lightning_LI*.parquet'))
    c1_glm_files = sorted(parquet_path.glob('EC_lightning_GLM*.parquet'))

    # crete STAC items for the C1 LI files collection
    for file in c1_li_files:
        _add_parquet_item(collection, file, parquet_dir, output_dir, 'group_time', li_vars,
                          'Lightning groups within EarthCARE MSI frame', 'MTG-LI')

    ## crete STAC items for the C1 GLM files collection
    for file in c1_glm_files:
        _add_parquet_item(collection, file, parquet_dir, output_dir, 'group_time', glm_vars,
                          'Lightning groups within EarthCARE MSI frame', 'GOES-GLM')

    # save the collection
    if list(collection.get_items()):
        collection.update_extent_from_items()
        catalog.add_child(collection)

    # ## Create the EarthCARE along-track lightning counts collection

    collectionid = "earthcare-along-track-lightning"
    description = "The along-track lightning counts product provides lightning statistics collocated with EarthCARE CPR observations along the satellite nadir track. For each CPR sample, the dataset quantifies the number of lightning groups detected by geostationary satellites within defined spatial and temporal windows centred on the observation point. The dataset is distributed as Parquet files, with separate files for each lightning data source (MTG-LI and GOES-GLM)."
    collection = Collection.from_dict(

    {
      "type": "Collection",
      "id": collectionid,
      "stac_version": "1.1.0",
      "title": "EarthCARE along-track lightning counts",
      "description": description,
      "extent": {
        "spatial": {
          "bbox": [
            [-180,
             -90,
             180,
             90]
          ]
        },
        "temporal": {
          "interval": [
            [
              None,
              None
            ]
          ]
        }
      },
      "license": "CC-BY-4.0",
      "links": [],
      "created": created,
      "summaries": {
        "platform": [
          "EarthCARE",
          "MTG-I1",
          "GOES-16",
          "GOES-18",
          "GOES-19",
        ],
        "instruments": [
          "CPR",
          "ATLID",
          "LI",
          "GLM"
        ]
      }

    }

    )

    # Extract all variable metadata from sample nc files.
    c2li_vars = c2glm_vars = {}
    if source_dir is not None:
        track_path = source_dir / 'track_counts'
        c2glm_vars = _variable_metadata(track_path, 'CPR-GLM-sum_*.nc')
        c2li_vars = _variable_metadata(track_path, 'CPR-LI-sum_*.nc')

    # Generate stac items per file type and add to the collection.
    parquet_path = parquet_dir / 'track_counts_parquet'
    c2_glm_file = parquet_path / 'EC_track_lightning_GLM.parquet'
    c2_li_file = parquet_path / 'EC_track_lightning_LI.parquet'
    _add_parquet_item(collection, c2_glm_file, parquet_dir, output_dir, 'time', c2glm_vars,
                      'Lightning groups count along EarthCARE nadir track', 'GOES-GLM')
    _add_parquet_item(collection, c2_li_file, parquet_dir, output_dir, 'time', c2li_vars,
                      'Lightning groups count along EarthCARE nadir track', 'MTG-LI')

    # save the collection
    if list(collection.get_items()):
        collection.update_extent_from_items()
        catalog.add_child(collection)

    # ## Create the EarthCARE lightning storm catalogue collection

    collectionid = "earthcare-storm-catalogue"
    description = "The lightning storm catalogue provides a set of lightning clusters sampled along the EarthCARE nadir track by its active sensors (CPR and ATLID). Each cluster represents an electrically active region within a convective system, such as an individual convective cell, anvil lightning, or a broader multicellular storm area. The dataset is distributed as Parquet files: one containing cluster-level descriptors (e.g., lightning counts, spatial extent) and another describing the temporal evolution of lightning activity within each cluster in a ±1 hour window around the EarthCARE overpass."
    collection = Collection.from_dict(

    {
      "type": "Collection",
      "id": collectionid,
      "stac_version": "1.1.0",
      "title": "EarthCARE lightning storm catalogue",
      "description": description,
      "extent": {
        "spatial": {
          "bbox": [
            [-180,
             -90,
             180,
             90]
          ]
        },
        "temporal": {
          "interval": [
            [
              None,
              None
            ]
          ]
        }
      },
      "license": "CC-BY-4.0",
      "links": [],
      "created": created,
      "summaries": {
        "platform": [
          "EarthCARE",
          "MTG-I1",
          "GOES-16",
          "GOES-18",
          "GOES-19",
        ],
        "instruments": [
          "MSI",
          "CPR",
          "ATLID",
          "LI",
          "GLM"
        ]
      }

    }

    )

    # All variable metadata

    c3 = {
        "unique_id": "Unique identifier of the lightning cluster (earthcare_id + source + cluster_id)",
        "earthcare_id": "Orbit/frame identifier of the EarthCARE overpass",
        "source": "Lightning data source: LI (MTG) or GLM (GOES)",
        "parent_cluster_id": "Parent lightning cluster identifier",
        "cluster_id": "Lightning cluster identifier",
        "surface_type": "Surface classification at cluster location (land, water, coast)",
        "peak_datetime": "Time of CPR sample with maximum lightning activity",
        "peak_lat": "Latitude of CPR sample with maximum lightning activity",
        "peak_lon": "Longitude of CPR sample with maximum lightning activity",
        "peak_lightning": "Maximum lightning group count at a CPR sample",
        "nadir_lightning": "Lightning group count within ±2.5 min and ±2.5 km of CPR nadir track",
        "cluster_lightning": "Lightning group count within ±2.5 min of CPR peak time (any distance)",
        "cluster_area_km2": "Area of cluster in km2",
        "cluster_mean_lat": "Mean latitude of lightning groups within ±2.5 min of CPR peak time",
        "cluster_mean_lon": "Mean longitude of lightning groups within ±2.5 min of CPR peak time",
        "cluster_dist_km": "Minimum distance (km) between CPR track and mean cluster location",
        "first_lightning_min": "Minute offset of first lightning in parent cluster relative to peak_datetime",
        "last_lightning_min": "Minute offset of last lightning in parent cluster relative to peak_datetime",
        "duration_min": "Parent cluster duration in minutes",
        "travel_km": "Shortest distance (km) between first and last lightning locations in parent cluster",
        "minute_counts": "Lightning group counts in parent cluster per minute (−60…+60) relative to peak_datetime",
        "minute_mean_lat": "Mean lightning latitude in parent cluster per minute (−60…+60) relative to peak_datetime",
        "minute_mean_lon": "Mean lightning longitude in parent cluster per minute (−60…+60) relative to peak_datetime",
        "missing_peak_minutes": "Total minutes of missing data overlapping ±2.5 min around peak_datetime",
        "masked_minute_counts": "Lightning group counts per minute (−60…+60) with missing intervals masked as null",
        "minute_offset": "Minute offset (−60…+60) relative to peak_datetime",
        "absolute_time": "Absolute time corresponding to minute_offset relative to peak_datetime",
        "lightning_count": "Lightning group count in parent cluster per minute (−60…+60) relative to peak_datetime",
        "masked_lightning_count": "Lightning group count in parent cluster per minute (−60…+60) relative to peak_datetime, with missing intervals masked as null",
        "latitude": "Mean lightning latitude in parent cluster per minute (−60…+60) relative to peak_datetime",
        "longitude": "Mean lightning longitude in parent cluster per minute (−60…+60) relative to peak_datetime",
      }

    # Generate stac items per file type and add to the collection.
    c3evol_file = parquet_dir / 'EC_lightning_cluster_evolution.parquet'
    c3summary_file = parquet_dir / 'EC_lightning_clusters.parquet'

    # Add the summary and the evolution files
    _add_parquet_item(collection, c3summary_file, parquet_dir, output_dir, 'peak_datetime', c3,
                      'Lightning storm catalogue statistics')
    _add_parquet_item(collection, c3evol_file, parquet_dir, output_dir, 'absolute_time', c3,
                      'Lightning storm catalogue evolution statistics')

    # save the collection
    if list(collection.get_items()):
        collection.update_extent_from_items()
        catalog.add_child(collection)

    # Include the EarthCARE ID mapping alongside the data it describes.
    mapping_file = parquet_dir / 'earthcare_id_mapping.parquet'
    first_item = next(catalog.get_items(recursive=True), None)
    if mapping_file.exists() and first_item is not None:
        asset_path = output_dir / 'parquet' / mapping_file.name
        if mapping_file.resolve() != asset_path.resolve():
            shutil.copy2(mapping_file, asset_path)
        first_item.add_asset('earthcare_id_mapping', pystac.Asset(
            href=str(asset_path.resolve()), media_type='application/x-parquet', roles=['metadata']
        ))

    # Save one root catalog.json with relative links to the collections, items and assets.
    catalog.normalize_hrefs(str(output_dir.resolve()))
    catalog.make_all_asset_hrefs_relative()
    catalog.save(catalog_type=pystac.CatalogType.SELF_CONTAINED)
    print(f'Saved {sum(1 for _ in catalog.get_items(recursive=True))} Items → {output_dir / "catalog.json"}')


if __name__ == '__main__':
    main()
