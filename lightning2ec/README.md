# lightning2ec

`lightning2ec` is a Python pipeline to collocate **EarthCARE MSI/CPR observations** with **satellite lightning detections** from **MTG-LI** and **GOES-GLM**.

The pipeline processes a user-defined date range and automatically:
- reads a local EarthCARE STAC catalogue or queries **EarthCARE MSI and CPR data** from ESA MAAP
- (down)loads **lightning observations**
- performs spatial–temporal collocation
- outputs matched datasets for further analysis

## Getting Started

First clone the repository and navigate to the project directory:

```bash
git clone https://github.com/piskalab/lightning2earthcare.git
cd lightning2earthcare
```
You can install the required dependencies either using **conda** or **pip**.

**Option 1: Conda environment**<br>
Create the environment:
```bash
conda env create -f environment.yaml
```
Activate the environment:
```bash
conda activate Lightning2ec
```

**Option 2: pip installation**<br>
Create a Python environment:
```bash
python -m venv lightning2ec-env
source lightning2ec-env/bin/activate
```
Install the dependencies:
```bash
pip install -r requirements.txt
```

**Option 3: pixi installation**<br>
With Pixi (locked environment):
```bash
pixi install --locked
pixi run --locked cli --help
```

## Credentials

The pipeline requires credentials for EUMETSAT Data Store and ESA MAAP API.

All credentials are stored in a `credentials.txt` file located **one directory above** the `lightning2ec` package.
Set `LIGHTNING2EC_CREDENTIALS_FILE` to use another file - and alternatively pass the keys below as environment variables (env variables take precedence)

### Creating `credentials.txt`

Create a plain text file named `credentials.txt` with the following format:
```
EUMETSAT_KEY=your_eumetsat_key_here
EUMETSAT_SECRET=your_eumetsat_secret_here
CLIENT_ID=offline-token
CLIENT_SECRET=p1eL7uonXs6MDxtGbgKdPVRAmnGxHpVE
OFFLINE_TOKEN=your_earthcare_longlasting_token_here
```

**Notes**
- Do **not** use quotes around the values.  
- Ensure there are no trailing spaces or extra characters.
- Keep this file private and do not commit it to GitHub.

### Environment variables

Alternatively, export all five values before running the local CLI:

```bash
export EUMETSAT_KEY='your_eumetsat_key_here'
export EUMETSAT_SECRET='your_eumetsat_secret_here'
export CLIENT_ID='offline-token'
export CLIENT_SECRET='p1eL7uonXs6MDxtGbgKdPVRAmnGxHpVE'
export OFFLINE_TOKEN='your_earthcare_longlasting_token_here'
```

Set all five together; if any is set, the credentials file is not read. The [CWL examples](../README.md#run-with-cwl) use the `credentials_file` input instead.

### EarthCARE access token

The pipeline uses a **90-day offline token** to obtain temporary access tokens for the MAAP API.

First create an EO Sign In account: https://eoiam-idp.eo.esa.int/

Then generate an offline token here: https://portal.maap.eo.esa.int/ini/services/auth/token/90dToken.php

Place the generated value in the OFFLINE_TOKEN field of credentials.txt.
The offline token is valid for 90 days and must be renewed after it expires.

See the [ESA EarthCARE authentication example](https://catalog.maap.eo.esa.int/doc/examples/ESAMAAP_ecdataaccess.html#token) for token usage and the shared `CLIENT_ID` and `CLIENT_SECRET` values above.

### EUMETSAT Data Store credentials

Create a EUMETSAT account to access the Data Store:
https://user.eumetsat.int/cas/login

Place the generated Data Store API credentials in the EUMETSAT_KEY and EUMETSAT_SECRET fields of credentials.txt.

Retrieve your **Consumer key** and **Consumer secret** on the [API Key Management page](https://api.eumetsat.int/api-key/). See the [EUMDAC guide](https://user.eumetsat.int/resources/user-guides/eumetsat-data-access-client-eumdac-guide) for setup and authentication instructions.

## Usage

Run the pipeline via the CLI module for a defined date range:
```bash
python -m lightning2ec.cli \
    --lightning-dir PATH_TO_LIGHTNING_DATA \
    --start-date 2025-08-01 \
    --end-date 2025-09-30
```
By default the pipeline processes **all supported lightning platforms**:
- MTG-I1
- GOES-16/19
- GOES-18

Example restricting to **MTG-LI only**:
```bash
python -m lightning2ec.cli \
    --lightning-dir "PATH_TO_LIGHTNING_DATA" \
    --start-date 2025-08-01 \
    --end-date 2025-09-30 \
    --lightning-platform MTG-I1
```

## Podman

Build from the repository root:
```bash
podman build -t lightning2earthcare:local .
mkdir -p results
```

### 1. Collocation

Run a date range (using `credentials.txt`):
```bash
podman run --rm --init \
    --env-file "credentials.txt" \
    --mount "type=bind,source=$(pwd)/results,target=/data" \
    lightning2earthcare:local \
    --lightning-dir /data --log-dir /data/logs \
    --start-date 2025-08-01 --end-date 2025-08-02
```

For selected EarthCARE products, first save their STAC metadata. The helper also accepts
`--start-date` and `--end-date` instead of IDs:
```bash
pixi run --locked python -m cwl.helper_create_earthcare_catalog \
    --item-id ECA_EXBA_MSI_COP_2A_20250731T235647Z_20250801T004508Z_06676A \
    --item-id ECA_EXBA_CPR_FMR_2A_20250731T235647Z_20250801T022217Z_06676A \
    --frame A --output-dir cwl/earthcare
```

Pass that catalogue directory to the pipeline; dates and frame/product filters still apply:
```bash
podman run --rm --init \
    --env-file "credentials.txt" \
    --mount "type=bind,source=$(pwd)/results,target=/data" \
    --mount "type=bind,source=$(pwd)/cwl/earthcare,target=/earthcare,readonly" \
    lightning2earthcare:local \
    --lightning-dir /data --log-dir /data/logs \
    --start-date 2025-07-31 --end-date 2025-07-31 \
    --earthcare-catalog /earthcare
```

### 2. Create storm catalogue

```bash
podman run --rm --init \
    --mount "type=bind,source=$(pwd)/results,target=/data" \
    lightning2earthcare:local create_storm_catalogue \
    --lightning-groups-dir /data/lightning_groups \
    --track-counts-dir /data/track_counts --output /data/catalogue.json
```

### 3. Convert to Parquet

```bash
podman run --rm --init \
    --mount "type=bind,source=$(pwd)/results,target=/data" \
    lightning2earthcare:local post_process_nc_to_parquet \
    --catalogue /data/catalogue.json --source-dir /data --output-dir /data/parquet
```

### 4. Create STAC catalogue

```bash
podman run --rm --init \
    --mount "type=bind,source=$(pwd)/results,target=/data" \
    lightning2earthcare:local create_stac_catalogue \
    --parquet-dir /data/parquet --source-dir /data --output-dir /data/stac
```

The output contains `catalog.json`, STAC metadata and copies of the referenced Parquet files.
The CWL job uses `cwl/earthcare` as its input Directory and returns this STAC output Directory.
The helper downloads metadata only; EarthCARE product files are read from their HTTPS URLs during processing.
