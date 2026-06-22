# proton/bootstrap

`justjavac/proton/bootstrap` loads Proton app configuration.

It decodes `moon.proton` into runtime manifests and project tooling metadata.
It does not install extensions or create windows.

Primary entry points:

- `load_config_manifest_from_file(...)`
- `load_proton_project_config_from_file(...)`
- `load_proton_project_summary_from_file(...)`
- `load_runtime_manifest_from_json(...)`
