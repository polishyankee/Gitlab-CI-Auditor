# Backlog

This backlog turns the high-level rule catalog into implementable work items.

## P0

- Add explicit coverage-vs-execution scoring so unit test execution and published coverage are separate checks.
- Expand downstream support for imported YAML snapshots from external child and multi-project pipelines.
- Add a persistent scan-history storage backend and trend dashboard views.
- Add a rule DSL so new rules can be added without editing the core analyzer for every change.
- [x] Add policy-pack validation to fail fast on malformed JSON or unsupported keys.

## P1

- Expand SBOM, DAST, secret-detection, and IaC rules with organization-specific severity tuning and package-manager aware policies.
- Add remote include pinning checks for templates and external project includes.
- Add runner risk checks for Docker-in-Docker, privileged mode, and unsafe executor settings.

## P2

- Add diff mode to compare two `.gitlab-ci.yml` revisions.
- [x] Export findings as SARIF and JUnit-style machine-readable outputs.
- Highlight critical path and gate locations directly on the pipeline graph.
- Add organizational severity overrides per rule pack.
- Extend trend reporting with repository baselines, branch comparisons, and release milestone snapshots.

## P3

- Package the auditor as a Ruby gem.
- Publish a container image for CI self-auditing.
- Add repository templates for common onboarding scenarios.
- Add sample rule packs for platform, regulated, and internal-library teams.
