# Roadmap

## Recently Delivered

- [x] stack-aware SAST policy enforcement for `.NET`, `Node / JS`, `Java`, `Python`, `Go`, `Ruby`, and `PHP`
- [x] policy-pack driven accepted SAST tool families through `stack_sast_requirements`
- [x] richer scan detection for artifact, dependency, and container-image scanners
- [x] first-class SBOM, secret-detection, IaC, and DAST controls with policy-pack support
- [x] multi-project graph ingestion through JSON context manifests
- [x] historical trend dashboards backed by a persistent JSON history store
- [x] diff mode for comparing two pipeline revisions through CLI and report views
- [x] organization-specific severity tuning through policy files
- [x] graph legend, gate overlays, and critical-path highlighting in the HTML report
- [x] fail-fast policy-pack validation for unsupported keys and malformed overrides
- [x] machine-readable `SARIF` and `JUnit` exports for CI integration
- [x] OWASP SAMM v2 `Implementation` benchmark for `Secure Build`, `Secure Deployment`, and `Defect Management`
- [x] report and GUI support for benchmark views, detected security tooling, and remediation context
- [x] explicit benchmark detection signals and per-practice rule mapping in the `OWASP SAMM` tab
- [x] question-level mapping for all upstream OWASP SAMM `Implementation` files (`I-SB-*`, `I-SD-*`, `I-DM-*`)

## Near Term

- [x] rule-pack support for organization-specific SSDLC baselines
- [x] stronger `rules:changes` semantics
- [x] explicit distinction between "tests executed" and "coverage reported"
- [x] richer downstream support for external child pipelines through imported YAML snapshots
- [x] HTML report export variants such as JSON bundle, CSV, and PDF

## Mid Term

- [ ] rule DSL for adding new checks without editing core analyzer code
- [x] SARIF or JUnit style output for CI integration
- [x] diff mode to compare two pipeline revisions
- [x] policy severity tuning per organization
- [x] graph legend, gate overlays, and critical path highlighting
- [ ] stack-aware policy rules for artifact scanning, container scanning, and package-manager specific dependency analysis
- [ ] benchmark expansion beyond SAMM `Implementation` into additional SAMM business functions where CI/CD evidence is meaningful
  Reviewed: not checked yet. `Implementation` is now covered down to the upstream question level, but additional business functions still need dedicated source mapping and heuristics before the benchmark can be expanded honestly.

## Long Term

- [x] multi-project pipeline graph ingestion
- [x] historical trend dashboards
- [ ] approval rules for production deployment gates
- [x] SBOM, DAST, secret-detection, and IaC policy extensions
- [ ] packaging as a standalone gem or container image
