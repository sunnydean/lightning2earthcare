cwlVersion: v1.2
$graph:
- class: CommandLineTool
  id: lightning2ec
  label: Multi-sensor observation matching
  doc: Match lightning and EarthCARE observations by location and time.
  baseCommand:
  - lightning2ec
  requirements:
    DockerRequirement:
      dockerPull: ghcr.io/sunnydean/lightning2earthcare:latest
    EnvVarRequirement:
      envDef:
        LIGHTNING2EC_CREDENTIALS_FILE: $(inputs.credentials_file.path)
        PYTHONPATH: /app
    NetworkAccess:
      networkAccess: true
  inputs:
    lightning_dir:
      type: string
      default: collocation_data
      inputBinding:
        prefix: --lightning-dir
      doc: Lightning downloads and collocation outputs.
    log_dir:
      type: string
      default: logs
      inputBinding:
        prefix: --log-dir
      doc: Monthly log directory.
    start_date:
      type: string
      inputBinding:
        prefix: --start-date
      doc: Start date (YYYY-MM-DD).
    end_date:
      type: string
      inputBinding:
        prefix: --end-date
      doc: End date (YYYY-MM-DD).
    earthcare_catalog:
      type: Directory?
      inputBinding:
        prefix: --earthcare-catalog
      doc: EarthCARE directory containing catalog.json.
    products:
      type:
      - 'null'
      - type: array
        items: string
        inputBinding:
          prefix: --product
      default:
      - MSI_COP_2A
      - CPR_FMR_2A
      doc: EarthCARE products to process.
    frames:
      type:
      - 'null'
      - type: array
        items: string
        inputBinding:
          prefix: --frame
      default:
      - A
      - B
      - D
      - E
      - F
      - H
      doc: Orbit frames to include.
    half_window_minutes:
      type: int?
      default: 60
      inputBinding:
        prefix: --half-window
      doc: Lightning integration half-window (minutes).
    lightning_platforms:
      type:
      - 'null'
      - type: array
        items: string
        inputBinding:
          prefix: --lightning-platform
      default:
      - MTG-I1
      - GOES-16
      - GOES-18
      - GOES-19
      doc: Lightning platforms to include.
    distance_threshold_km:
      type: float?
      default: 5.0
      inputBinding:
        prefix: --distance-threshold
      doc: CPR track distance threshold (km).
    time_threshold_s:
      type: int?
      default: 300
      inputBinding:
        prefix: --time-threshold
      doc: CPR acquisition time threshold (seconds).
    credentials_file:
      type: File
      doc: EUMETSAT and ESA MAAP credentials file.
  outputs:
    source_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.lightning_dir)
      doc: Lightning groups and track counts.
    lightning_groups_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.lightning_dir)/lightning_groups
      doc: Collocated lightning groups in NetCDF.
    track_counts_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.lightning_dir)/track_counts
      doc: Along-track CPR counts in NetCDF.
    log_dir_out:
      type: Directory?
      outputBinding:
        glob: $(inputs.log_dir)
      doc: Monthly processing logs.
  s:hasPart:
  - s:identifier: cluster_2
    s:name: Pipeline CLI command
    s:description: Run observation matching for the selected dates.
  - s:identifier: cluster_3
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#collocation
    s:name: Multi-sensor observation matching
    s:description: Match lightning and EarthCARE observations by location and time.
  - s:identifier: cluster_6
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#selection
    s:name: Satellite observation discovery
    s:description: Find satellite observations by time, coverage and product.
- class: CommandLineTool
  id: create_storm_catalogue
  label: Storm characterisation
  doc: Estimate storm location, size, duration, movement and lightning activity.
  baseCommand:
  - create_storm_catalogue
  requirements:
    DockerRequirement:
      dockerPull: ghcr.io/sunnydean/lightning2earthcare:latest
    EnvVarRequirement:
      envDef:
        PYTHONPATH: /app
  inputs:
    lightning_groups_dir:
      type: Directory
      inputBinding:
        prefix: --lightning-groups-dir
      doc: Collocated lightning groups in NetCDF.
    track_counts_dir:
      type: Directory
      inputBinding:
        prefix: --track-counts-dir
      doc: Along-track CPR counts in NetCDF.
    output_filename:
      type: string?
      default: catalogue.json
      inputBinding:
        prefix: --output
      doc: Storm catalogue output path.
  outputs:
    catalogue_json:
      type: File
      outputBinding:
        glob: $(inputs.output_filename)
      doc: Storm catalogue in JSON.
  s:hasPart:
  - s:identifier: cluster_4
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#aggregation
    s:name: Storm characterisation
    s:description: Estimate storm location, size, duration, movement and lightning activity.
  - s:identifier: cluster_5
    s:name: Create storm catalogue CLI
    s:description: Combine storm summaries into a JSON catalogue.
- class: CommandLineTool
  id: post_process_nc_to_parquet
  label: Geospatial feature construction
  doc: Build GeoParquet features from observations and storm records.
  baseCommand:
  - post_process_nc_to_parquet
  requirements:
    DockerRequirement:
      dockerPull: ghcr.io/sunnydean/lightning2earthcare:latest
    EnvVarRequirement:
      envDef:
        PYTHONPATH: /app
  inputs:
    catalogue:
      type: File
      inputBinding:
        prefix: --catalogue
      doc: Storm catalogue in JSON.
    source_dir:
      type: Directory?
      inputBinding:
        prefix: --source-dir
      doc: Lightning groups and track counts.
    output_dir_name:
      type: string?
      default: parquet
      inputBinding:
        prefix: --output-dir
      doc: Output directory name.
  outputs:
    parquet_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.output_dir_name)
      doc: GeoParquet datasets.
  s:hasPart:
  - s:identifier: cluster_7
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#conversion
    s:name: Geospatial feature construction
    s:description: Build GeoParquet features from observations and storm records.
  - s:identifier: cluster_8
    s:name: Parquet postprocessing CLI
    s:description: Run GeoParquet export.
- class: CommandLineTool
  id: create_stac_catalogue
  label: Spatiotemporal dataset cataloguing
  doc: Catalogue dataset coverage, variables and assets in STAC.
  baseCommand:
  - create_stac_catalogue
  requirements:
    DockerRequirement:
      dockerPull: ghcr.io/sunnydean/lightning2earthcare:latest
    EnvVarRequirement:
      envDef:
        PYTHONPATH: /app
  inputs:
    parquet_dir:
      type: Directory
      inputBinding:
        prefix: --parquet-dir
      doc: GeoParquet datasets.
    source_dir:
      type: Directory?
      inputBinding:
        prefix: --source-dir
      doc: NetCDF source data for variable metadata.
    output_dir_name:
      type: string?
      default: stac
      inputBinding:
        prefix: --output-dir
      doc: Output directory name.
  outputs:
    stac_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.output_dir_name)
      doc: STAC catalogue and items.
  s:hasPart:
  - s:identifier: cluster_9
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#stac
    s:name: Spatiotemporal dataset cataloguing
    s:description: Catalogue dataset coverage, variables and assets in STAC.
  - s:identifier: cluster_10
    s:name: STAC catalogue generation CLI
    s:description: Assemble the STAC catalogue.
- class: Workflow
  id: main
  label: Lightning2EarthCARE storm analysis
  doc: Match observations, characterise storms and catalogue geospatial datasets.
  inputs:
    start_date:
      type: string
      label: Start date
      doc: Start date (YYYY-MM-DD).
    end_date:
      type: string
      label: End date
      doc: End date (YYYY-MM-DD).
    credentials_file:
      type: File
      label: Credentials file
      doc: EUMETSAT and ESA MAAP credentials file.
    earthcare_catalog:
      type: Directory?
      label: EarthCARE catalog directory
      doc: EarthCARE directory containing catalog.json.
    products:
      type:
      - 'null'
      - type: array
        items: string
      default:
      - MSI_COP_2A
      - CPR_FMR_2A
      label: EarthCARE products
      doc: EarthCARE products to process.
    frames:
      type:
      - 'null'
      - type: array
        items: string
      default:
      - A
      - B
      - D
      - E
      - F
      - H
      label: Orbit frames
      doc: Orbit frames to include.
    half_window_minutes:
      type: int?
      default: 60
      label: Integration half-window
      doc: Lightning integration half-window (minutes).
    lightning_platforms:
      type:
      - 'null'
      - type: array
        items: string
      default:
      - MTG-I1
      - GOES-16
      - GOES-18
      - GOES-19
      label: Lightning platforms
      doc: Lightning platforms to include.
    distance_threshold_km:
      type: float?
      default: 5.0
      label: Distance threshold
      doc: CPR track distance threshold (km).
    time_threshold_s:
      type: int?
      default: 300
      label: Time threshold
      doc: CPR acquisition time threshold (seconds).
  outputs:
    log_dir_out:
      type: Directory?
      outputSource: lightning2ec/log_dir_out
      label: Collocation log directory
      doc: Monthly processing logs.
    stac_dir:
      type: Directory
      outputSource: create_stac_catalogue/stac_dir
      label: STAC catalogue directory
      doc: STAC catalogue and items.
  steps:
    lightning2ec:
      run: '#lightning2ec'
      in:
        lightning_dir:
          default: collocation_data
        log_dir:
          default: logs
        start_date: start_date
        end_date: end_date
        credentials_file: credentials_file
        earthcare_catalog: earthcare_catalog
        products: products
        frames: frames
        half_window_minutes: half_window_minutes
        lightning_platforms: lightning_platforms
        distance_threshold_km: distance_threshold_km
        time_threshold_s: time_threshold_s
      out:
      - source_dir
      - lightning_groups_dir
      - track_counts_dir
      - log_dir_out
    create_storm_catalogue:
      run: '#create_storm_catalogue'
      in:
        lightning_groups_dir: lightning2ec/lightning_groups_dir
        track_counts_dir: lightning2ec/track_counts_dir
        output_filename:
          default: catalogue.json
      out:
      - catalogue_json
    post_process_nc_to_parquet:
      run: '#post_process_nc_to_parquet'
      in:
        catalogue: create_storm_catalogue/catalogue_json
        source_dir: lightning2ec/source_dir
        output_dir_name:
          default: parquet
      out:
      - parquet_dir
    create_stac_catalogue:
      run: '#create_stac_catalogue'
      in:
        parquet_dir: post_process_nc_to_parquet/parquet_dir
        source_dir: lightning2ec/source_dir
        output_dir_name:
          default: stac
      out:
      - stac_dir
  s:hasPart:
  - s:identifier: cluster_1
    s:name: CLI root entrypoint
    s:description: Expose workflow commands.
$namespaces:
  s: https://schema.org/
$schemas:
- https://schema.org/version/latest/schemaorg-current-https.rdf
s:softwareVersion: 0.1.0
