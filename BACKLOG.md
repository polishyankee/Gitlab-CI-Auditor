# Backlog

This backlog turns the high-level rule catalog into implementable work items.

## P0

- Add explicit coverage-vs-execution scoring so unit test execution and published coverage are separate checks.
- Expand downstream support for imported YAML snapshots from external child and multi-project pipelines.
- Add a rule DSL so new rules can be added without editing the core analyzer for every change.
- Add policy-pack validation to fail fast on malformed JSON or unsupported keys.

## P1

- Add DAST detection and policy enforcement for web-facing services.
- Add SBOM detection and scoring for build outputs.
- Add secret-detection and IaC scanning as first-class SSDLC controls.
- Add remote include pinning checks for templates and external project includes.
- Add runner risk checks for Docker-in-Docker, privileged mode, and unsafe executor settings.

## P2

- Add diff mode to compare two `.gitlab-ci.yml` revisions.
- Export findings as SARIF and JUnit-style machine-readable outputs.
- Highlight critical path and gate locations directly on the pipeline graph.
- Add organizational severity overrides per rule pack.
- Add historical trend and score drift reporting.

## P3

- Package the auditor as a Ruby gem.
- Publish a container image for CI self-auditing.
- Add repository templates for common onboarding scenarios.
- Add sample rule packs for platform, regulated, and internal-library teams.
