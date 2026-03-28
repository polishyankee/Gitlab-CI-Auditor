# Roadmap

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

## Long Term

- [ ] multi-project pipeline graph ingestion
- [ ] historical trend dashboards
- [ ] approval rules for production deployment gates
- [ ] SBOM, DAST, secret-detection, and IaC policy extensions
- [ ] packaging as a standalone gem or container image
