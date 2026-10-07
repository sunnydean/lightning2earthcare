cwlVersion: v1.2
$namespaces:
  s: https://schema.org/
s:softwareVersion: "0.1.0"
$graph:
  - id: main
    class: Workflow
    label: EarthCARE lightning collocation, storm catalogue, Parquet and STAC generation
    doc: Collocate satellite lightning with EarthCARE, summarise storms, and produce Parquet files and a STAC catalogue.

    inputs:
      start_date:
        type: string
        label: Start date
        doc: First processing date, in YYYY-MM-DD format.
      end_date:
        type: string
        label: End date
        doc: Last processing date, in YYYY-MM-DD format.
      credentials:
        type: File
        label: Credentials
        doc: Key-value file containing EarthCARE and EUMETSAT credentials.
      earthcare_catalog:
        type: Directory
        label: EarthCARE STAC catalogue
        doc: Input directory containing catalog.json and EarthCARE MSI/CPR Items referencing HTTPS HDF5 assets.
      lightning_platforms:
        type: string[]
        default: []
        label: Lightning platforms
        doc: Lightning platforms to include; an empty list uses the CLI defaults.
      frames:
        type: string[]
        default: []
        label: EarthCARE frames
        doc: EarthCARE orbit frames to include; an empty list uses the CLI defaults.
      half_window:
        type: int
        default: 60
        label: Half-window in minutes
        doc: Minutes before and after the EarthCARE observation for lightning selection.

    outputs:
      stac:
        type: Directory
        outputSource: create_stac_catalogue/stac

    steps:
      lightning2ec:
        run: "#lightning2ec"
        in:
          start_date: start_date
          end_date: end_date
          credentials: credentials
          earthcare_catalog: earthcare_catalog
          lightning_platforms: lightning_platforms
          frames: frames
          half_window: half_window
        out: [collocation]
      create_storm_catalogue:
        run: "#create_storm_catalogue"
        in:
          collocation: lightning2ec/collocation
        out: [catalogue]
      post_process_nc_to_parquet:
        run: "#post_process_nc_to_parquet"
        in:
          catalogue: create_storm_catalogue/catalogue
          collocation: lightning2ec/collocation
        out: [parquet]
      create_stac_catalogue:
        run: "#create_stac_catalogue"
        in:
          parquet: post_process_nc_to_parquet/parquet
          collocation: lightning2ec/collocation
        out: [stac]

  - id: lightning2ec
    class: CommandLineTool

    requirements:
      DockerRequirement:
        dockerPull: lightning2earthcare:local
      EnvVarRequirement:
        envDef:
          # CWL runs in its output directory, while the package lives in /app.
          PYTHONPATH: /app
          LIGHTNING2EC_CREDENTIALS_FILE: $(inputs.credentials.path)
      NetworkAccess:
        networkAccess: true

    # The image entrypoint activates Pixi and runs python -m lightning2ec.cli.
    baseCommand: lightning2ec
    arguments: [--lightning-dir, collocation, --log-dir, collocation/logs]

    inputs:
      start_date:
        type: string
        inputBinding:
          prefix: --start-date
      end_date:
        type: string
        inputBinding:
          prefix: --end-date
      credentials: File
      earthcare_catalog:
        type: Directory
        inputBinding:
          prefix: --earthcare-catalog
      lightning_platforms:
        type:
          type: array
          items: string
          inputBinding:
            prefix: --lightning-platform
        default: []
        inputBinding: {}
      frames:
        type:
          type: array
          items: string
          inputBinding:
            prefix: --frame
        default: []
        inputBinding: {}
      half_window:
        type: int
        default: 60
        inputBinding:
          prefix: --half-window

    outputs:
      collocation:
        type: Directory
        outputBinding:
          glob: collocation

  - id: create_storm_catalogue
    class: CommandLineTool

    requirements:
      DockerRequirement:
        dockerPull: lightning2earthcare:local
      EnvVarRequirement:
        envDef:
          PYTHONPATH: /app

    baseCommand: create_storm_catalogue
    arguments:
      - --lightning-groups-dir
      - $(inputs.collocation.path)/lightning_groups
      - --track-counts-dir
      - $(inputs.collocation.path)/track_counts
      - --output
      - catalogue.json

    inputs:
      collocation: Directory

    outputs:
      catalogue:
        type: File
        outputBinding:
          glob: catalogue.json

  - id: post_process_nc_to_parquet
    class: CommandLineTool

    requirements:
      DockerRequirement:
        dockerPull: lightning2earthcare:local
      EnvVarRequirement:
        envDef:
          PYTHONPATH: /app

    baseCommand: post_process_nc_to_parquet
    arguments: [--output-dir, parquet]

    inputs:
      catalogue:
        type: File
        inputBinding:
          prefix: --catalogue
      collocation:
        type: Directory
        inputBinding:
          prefix: --source-dir

    outputs:
      parquet:
        type: Directory
        outputBinding:
          glob: parquet

  - id: create_stac_catalogue
    class: CommandLineTool

    requirements:
      DockerRequirement:
        dockerPull: lightning2earthcare:local
      EnvVarRequirement:
        envDef:
          PYTHONPATH: /app

    baseCommand: create_stac_catalogue
    arguments: [--output-dir, stac]

    inputs:
      parquet:
        type: Directory
        inputBinding:
          prefix: --parquet-dir
      collocation:
        type: Directory
        inputBinding:
          prefix: --source-dir

    outputs:
      stac:
        type: Directory
        outputBinding:
          glob: stac
