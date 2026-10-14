cwlVersion: v1.2
$graph:
- class: CommandLineTool
  id: lightning2ec
  label: Lightning to EarthCARE collocation
  doc: Downloads and collocates satellite lightning data with EarthCARE CPR tracks.
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
      doc: Base directory for lightning downloads and collocated outputs.
    log_dir:
      type: string
      default: logs
      inputBinding:
        prefix: --log-dir
      doc: Directory where monthly log files are written.
    start_date:
      type: string
      inputBinding:
        prefix: --start-date
      doc: Start date for processing in YYYY-MM-DD format.
    end_date:
      type: string
      inputBinding:
        prefix: --end-date
      doc: End date for processing in YYYY-MM-DD format.
    earthcare_catalog:
      type: Directory?
      inputBinding:
        prefix: --earthcare-catalog
      doc: EarthCARE input directory containing catalog.json.
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
      doc: Half-window of lightning integration in minutes.
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
      doc: Distance threshold from CPR track in kilometers.
    time_threshold_s:
      type: int?
      default: 300
      inputBinding:
        prefix: --time-threshold
      doc: Temporal threshold from CPR acquisition in seconds.
    credentials_file:
      type: File
      doc: Credentials file providing API tokens for EUMETSAT and ESA MAAP.
  outputs:
    source_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.lightning_dir)
      doc: Base directory containing lightning groups and track counts.
    lightning_groups_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.lightning_dir)/lightning_groups
      doc: Directory containing collocated lightning groups NetCDF files.
    track_counts_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.lightning_dir)/track_counts
      doc: Directory containing along-track CPR counts NetCDF files.
    log_dir_out:
      type: Directory?
      outputBinding:
        glob: $(inputs.log_dir)
      doc: Directory containing monthly processing logs.
  s:hasPart:
  - s:identifier: cluster_2
    s:name: Pipeline CLI command
    s:description: Parse command-line arguments and run the EarthCARE-lightning collocation pipeline
      over a date range.
  - s:identifier: cluster_3
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#collocation
    s:name: Lightning data collocation processing
    s:description: Retrieve, cluster, parallax-correct, collocate, and output matched lightning
      observations and CPR track summaries.
  - s:identifier: cluster_6
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#selection
    s:name: Collocation runtime orchestration
    s:description: Orchestrate pipeline execution over date ranges, catalog lookups, source
      selection, and logging context.
- class: CommandLineTool
  id: create_storm_catalogue
  label: Create storm catalogue
  doc: Aggregates collocated lightning clusters and track counts into a storm catalogue.
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
      doc: Directory containing collocated lightning groups NetCDF files.
    track_counts_dir:
      type: Directory
      inputBinding:
        prefix: --track-counts-dir
      doc: Directory containing CPR track counts NetCDF files.
    output_filename:
      type: string?
      default: catalogue.json
      inputBinding:
        prefix: --output
      doc: Output path for the generated storm catalogue JSON file.
  outputs:
    catalogue_json:
      type: File
      outputBinding:
        glob: $(inputs.output_filename)
      doc: JSON storm catalogue summarizing lightning clusters.
  s:hasPart:
  - s:identifier: cluster_4
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#aggregation
    s:name: Storm catalogue file processor
    s:description: Extract lightning storm properties and along-track statistics from collocated
      NetCDF files.
  - s:identifier: cluster_5
    s:name: Create storm catalogue CLI
    s:description: Aggregate collocated lightning and CPR counts across all files into a unified
      JSON storm catalogue.
- class: CommandLineTool
  id: post_process_nc_to_parquet
  label: Convert NetCDF to GeoParquet
  doc: Converts collocated NetCDF datasets and storm catalogue to GeoParquet format.
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
      doc: Storm catalogue JSON file.
    source_dir:
      type: Directory?
      inputBinding:
        prefix: --source-dir
      doc: Collocation output directory containing lightning groups and track counts.
    output_dir_name:
      type: string?
      default: parquet
      inputBinding:
        prefix: --output-dir
      doc: Directory name for generated Parquet files.
  outputs:
    parquet_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.output_dir_name)
      doc: Directory containing converted GeoParquet datasets.
  s:hasPart:
  - s:identifier: cluster_7
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#conversion
    s:name: NetCDF and JSON to Parquet conversion
    s:description: Transform collocated NetCDF files and storm catalogue JSON into structured
      GeoParquet dataframes.
  - s:identifier: cluster_8
    s:name: Parquet postprocessing CLI
    s:description: Execute CLI conversion of collocated NetCDFs and storm catalogue to GeoParquet
      files.
- class: CommandLineTool
  id: create_stac_catalogue
  label: Create STAC catalogue
  doc: Builds a STAC catalogue organizing converted Parquet items and variable metadata.
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
      doc: Directory containing converted Parquet datasets.
    source_dir:
      type: Directory?
      inputBinding:
        prefix: --source-dir
      doc: Collocation output directory for NetCDF variable metadata extraction.
    output_dir_name:
      type: string?
      default: stac
      inputBinding:
        prefix: --output-dir
      doc: Directory name for the generated STAC catalogue.
  outputs:
    stac_dir:
      type: Directory
      outputBinding:
        glob: $(inputs.output_dir_name)
      doc: STAC catalogue directory containing catalog.json and items.
  s:hasPart:
  - s:identifier: cluster_9
    s:additionalType: ospd2026/registry/geoprocessing-activities.jsonld#stac
    s:name: STAC item generation helpers
    s:description: Extract NetCDF metadata and create STAC item records from Parquet dataset files.
  - s:identifier: cluster_10
    s:name: STAC catalogue generation CLI
    s:description: Generate a self-contained STAC catalogue organizing generated Parquet dataset
      collections.
- class: Workflow
  id: main
  label: Lightning to EarthCARE collocation pipeline
  doc: Collocates satellite lightning observations with EarthCARE overpasses and generates
    Parquet and STAC catalogues.
  inputs:
    start_date:
      type: string
      label: Start date
      doc: Start date for processing in YYYY-MM-DD format.
    end_date:
      type: string
      label: End date
      doc: End date for processing in YYYY-MM-DD format.
    credentials_file:
      type: File
      label: Credentials file
      doc: Path to credentials file with EUMETSAT and ESA MAAP tokens; replace placeholder
        /REPLACE_ME/credentials.json.
    earthcare_catalog:
      type: Directory?
      label: EarthCARE catalog directory
      doc: EarthCARE input directory containing catalog.json metadata.
    products:
      type:
      - 'null'
      - type: array
        items: string
      default:
      - MSI_COP_2A
      - CPR_FMR_2A
      label: EarthCARE products
      doc: EarthCARE products to process during collocation.
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
      doc: Orbit frames to include in processing.
    half_window_minutes:
      type: int?
      default: 60
      label: Integration half-window
      doc: Half-window of lightning integration in minutes.
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
      doc: Lightning platforms to include in processing.
    distance_threshold_km:
      type: float?
      default: 5.0
      label: Distance threshold
      doc: Distance threshold from CPR track in kilometers.
    time_threshold_s:
      type: int?
      default: 300
      label: Time threshold
      doc: Temporal threshold from CPR acquisition in seconds.
  outputs:
    log_dir_out:
      type: Directory?
      outputSource: lightning2ec/log_dir_out
      label: Collocation log directory
      doc: Directory containing monthly processing logs from collocation.
    stac_dir:
      type: Directory
      outputSource: create_stac_catalogue/stac_dir
      label: STAC catalogue directory
      doc: STAC catalogue directory containing catalog metadata and items.
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
    s:description: Define the top-level Click group command for the Lightning2EarthCARE pipeline
      CLI.
$namespaces:
  s: https://schema.org/
$schemas:
- https://schema.org/version/latest/schemaorg-current-https.rdf
s:softwareVersion: 0.1.0
