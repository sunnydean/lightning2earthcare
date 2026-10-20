# Lightning2EarthCARE - D120 worked example

OGC API - Processes metadata based on the successful local CWLProv run of **12 October 2026**: four commands, ten code clusters and five provisional activity terms.

Our contribution is **code-grounded vocabulary discovery**: AI interprets code clusters and I/O evidence to propose activity descriptions, refined through vocabulary matching and review. Improved description quality remains a working hypothesis.

| File | Origin |
| --- | --- |
| [annotations.ttl](annotations.ttl) | Manual cluster, term, run and STAC-source mappings. |
| [process.json](process.json) | Manually mapped from the CWL interface. |
| [provenance.jsonld](provenance.jsonld) | Reviewed, manually formatted execution provenance. |
| [results.json](results.json) | Manually mapped from recorded outputs and provenance. |
| [Registry](registry/geoprocessing-activities.jsonld) | Five cluster-derived definitions with three related-term links. |
| [Cluster data](clusters/clusters.json) / [graph](clusters/labelled-clusters.html) | Saved notebook outputs. |
| [Report](report/d001-sunnydean-contribution.md) | Method, evidence, vocabulary mappings and validation details. |

## Export

Run from the repository root using the existing Pixi environment:

```sh
/Users/dean/code/ai-workflow-definitions/gen-ogc-apppackage/.pixi/envs/default/bin/python cwl/ospd2026/export_provenance.py
```

The script exports directly to `provenance.jsonld`, omitting credential details and file contents. It stops if that file exists, protecting manual edits. Move the file aside only when regenerating; then apply profile formatting and timezone normalization before validation.

## Validation and scope

Checked **14 October 2026**: CWL/job checks, OGC process/results schemas, shared PROV and 27 input STAC checks passed. Source comparisons confirmed four process runs, six artifact connections and ten cluster mappings. These results apply to the reviewed files; a fresh export requires profile cleanup and revalidation.

This is a local metadata example, not an API execution or full service-conformance claim. Terms remain provisional. Original `cwl/provenance/` and `cwl/results/` are excluded from Git; the original bundle contains captured credentials. See the report for source links and remaining limitations.
