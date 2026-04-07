# Changelog

## v0.3.0

Release date target: April 2026

### Highlights

- Added CI-ready `SARIF` and `JUnit` exports for machine-readable audit consumption.
- Added fail-fast validation for malformed or unsupported policy-pack JSON.
- Improved repository discoverability with a stronger README opening, quick-start flow, social-preview asset, and GitHub metadata pack.

### Product Capabilities In This Release

- stack-aware SAST policy enforcement
- artifact, dependency, and image-scan detection
- SBOM, secret-detection, IaC, and DAST controls
- multi-project context ingestion and downstream snapshot support
- OWASP SAMM `Implementation` benchmark views and question mapping
- historical trend dashboards
- diff mode for comparing pipeline revisions
- HTML, PDF, CSV, JSON bundle, SARIF, and JUnit exports

### Verification

- `ruby -I lib:test test/run_all.rb`
- `./bin/gitlab-ci-auditor scan examples/pipelines/legacy_monolith.gitlab-ci.yml --format sarif --output /tmp/gitlab-ci-auditor.sarif.json`
- `./bin/gitlab-ci-auditor scan examples/pipelines/legacy_monolith.gitlab-ci.yml --format junit --output /tmp/gitlab-ci-auditor.junit.xml`

### Notes

- Local Docker validation still requires a running Docker daemon.
- The GitHub `Release` workflow publishes the multi-arch GHCR image and attaches generated example reports.
