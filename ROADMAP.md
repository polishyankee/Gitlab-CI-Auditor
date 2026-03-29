# Roadmap

## Recently Delivered

- [x] stack-aware SAST policy enforcement for `.NET`, `Node / JS`, `Java`, `Python`, `Go`, `Ruby`, and `PHP`
- [x] policy-pack driven accepted SAST tool families through `stack_sast_requirements`
- [x] richer scan detection for artifact, dependency, and container-image scanners
- [x] OWASP SAMM v2 `Implementation` benchmark for `Secure Build`, `Secure Deployment`, and `Defect Management`
- [x] report and GUI support for benchmark views, detected security tooling, and remediation context

## Near Term

- [x] rule-pack support for organization-specific SSDLC baselines
- [x] stronger `rules:changes` semantics
- [x] explicit distinction between "tests executed" and "coverage reported"
- [x] richer downstream support for external child pipelines through imported YAML snapshots
- [x] HTML report export variants such as JSON bundle, CSV, and PDF

## Mid Term

- [ ] rule DSL for adding new checks without editing core analyzer code
- [ ] SARIF or JUnit style output for CI integration
- [ ] diff mode to compare two pipeline revisions
- [ ] policy severity tuning per organization
- [ ] graph legend, gate overlays, and critical path highlighting
- [ ] stack-aware policy rules for artifact scanning, container scanning, and package-manager specific dependency analysis
- [ ] benchmark expansion beyond SAMM `Implementation` into additional SAMM business functions where CI/CD evidence is meaningful

## Long Term

- [ ] multi-project pipeline graph ingestion
- [ ] historical trend dashboards
- [ ] approval rules for production deployment gates
- [ ] SBOM, DAST, secret-detection, and IaC policy extensions
- [ ] packaging as a standalone gem or container image
