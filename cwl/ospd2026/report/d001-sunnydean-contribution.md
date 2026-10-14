# Lightning2EarthCARE - D120 contribution

**Role:** D120 - OGC API Processes Profiler  
**Status:** Local worked example for consortium review

## Part A - Main report section

This contribution provides an OGC API - Processes [process description](../process.json), [results metadata](../results.json) and [provenance](../provenance.jsonld) for [Lightning2EarthCARE](http://opensciencedata.esa.int/products/earthcare-frame-lightning/collection_v1). It connects **four executable steps, five provisional activity terms and a successful local execution**: observation collocation, storm catalogue generation, Parquet export and STAC creation.

Existing registry terms are difficult to reuse directly because their scope differs or covers only part of an operation. We propose a term hierarchy supporting different levels of granularity and greater reuse across workflows.

## Part B - Contribution details

### B1. Proposed activities and registry reuse

The [registry](../registry/geoprocessing-activities.jsonld) describes five scientific activities within the workflow as provisional `ospd:GeoprocessingActivity` terms.

| Provisional activity | Related registry term | Parent command |
| --- | --- | --- |
| Spatiotemporal observation collocation | [GA047 Data Acquisition](https://github.com/Kurrawong/ospd-data/blob/main/resources/registers/voyager/items/GA047.ttl) | `lightning2ec` |
| Storm property summarisation | No suitable match found | `create_storm_catalogue` |
| Spatiotemporal observation selection | [GA020 Filter geometries](https://github.com/Kurrawong/ospd-data/blob/main/resources/registers/52north/items/GA020.ttl) | `lightning2ec` |
| Geospatial tabular conversion | [GA044 Field Normalization](https://github.com/Kurrawong/ospd-data/blob/main/resources/registers/voyager/items/GA044.ttl) | `post_process_nc_to_parquet` |
| STAC item generation | No suitable match found | `create_stac_catalogue` |

The three existing terms cover acquisition, geometry filtering and field normalisation. Their `skos:relatedMatch` links express partial overlap, not equivalence.

Proposed broader/narrower paths include **Data transformation → Tabular conversion → Geospatial tabular conversion** and **Metadata creation → STAC item generation**. These would support shared general descriptions and precise specialisations. The hierarchy and term mappings require consortium review.

CWL `s:hasPart` descriptions reference terms through `s:additionalType`; [annotations](../annotations.ttl) link them to commands and recorded runs. Internal operations are descriptive, without separate observed executions.

### B2. Execution evidence and metadata

The [executed CWL](../../provenance/snapshot/package.cwl) and [engine log](../../provenance/metadata/logs/engine.3d85b6b6-3adf-4c89-b04a-974e47ad03a2.txt) record success with Podman, CWLProv and `ghcr.io/sunnydean/lightning2earthcare:latest`. Provenance identifies four process runs, their parameters, timestamps and **six artifact connections**. Results metadata identifies two outputs with provenance links. The [CWL package](../../package.cwl) matches the snapshot's executable content.

### B3. Validation and limitations

Passed: implemented CWL/job checks, OGC process/results schemas, IPT results and shared PROV schemas, 27 STAC metadata checks, and JSON-LD/relationship checks. See the [README](../README.md) for scope. The [workflow](https://ogcincubator.github.io/bblocks-openscience/bblock/ogc.osc.api-profiles.processes.workflow) and [OSPD](https://ogcincubator.github.io/bblocks-openscience/bblock/ogc.osc.api-profiles.processes.ospd) building blocks remain references for consortium profile review.

This is a local metadata example, without a hosted API execution or full conformance claim. Open issues include Directory/STAC packaging and missing upstream provenance. Source timestamps assume Europe/London; no image digest is available. Original execution records and outputs remain private, so their links resolve only locally.

### B4. AI and generation

The [generator](https://github.com/sunnydean/gen-ogc-apppackage) grounds AI descriptions in function clusters and resource I/O. Ten clusters informed five proposed terms, refined through vocabulary matching and review.

Saved [notebook outputs](../clusters/clusters.json) and the [graph](../clusters/labelled-clusters.html) ([figure](../clusters/labelled-clusters.svg)) retain this analysis. Improved description fidelity remains a hypothesis; these interpretations are separate from execution evidence.

| Cluster | Role | What it does |
| --- | --- | --- |
| C1 | Main CLI entrypoint | Groups the available workflow commands under one command-line interface. |
| C2 | Collocation command | Reads user options and starts collocation for the requested dates. |
| C3 | Collocation processing | Retrieves and groups lightning observations, applies parallax correction, matches them to EarthCARE observations and writes results. |
| C4 | Storm analysis | Extracts storm properties and along-track statistics from collocated data. |
| C5 | Storm catalogue command | Combines results across files into a JSON storm catalogue. |
| C6 | Collocation coordination | Queries catalogues, selects observation sources and manages processing dates and logging. |
| C7 | Geospatial table conversion | Converts collocated NetCDF data and storm catalogue records into GeoParquet tables. |
| C8 | Parquet export command | Launches the conversion using the supplied inputs and options. |
| C9 | STAC item creation | Extracts dataset metadata and creates STAC records linking to Parquet assets. |
| C10 | STAC catalogue command | Organises the generated datasets and item records into a STAC catalogue. |

The four executable steps collocate EarthCARE and lightning observations, summarise storms into a catalogue, export geospatial tables and describe the outputs in STAC. C1-C10 cover the command interfaces and internal processing supporting those steps.

