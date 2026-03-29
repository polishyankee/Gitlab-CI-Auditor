# Proposed Rule Catalog

This document defines the baseline rules the auditor should support. It separates what is already implemented from the next rules worth adding.

## Implemented Baseline Rules

### SSDLC Control Rules

1. Unit tests must run on every supported active pipeline path.
Evidence:
Dedicated test job, Maven or Gradle build without test-skip flags, or JaCoCo artifacts such as `jacoco.exec` and `jacoco.xml`.

2. SAST must be present and enforcing on every supported branch and merge request path.
Evidence:
Known scanners or GitLab SAST template inference, plus stack-specific accepted tool families from the active policy pack.

3. Artifact scanning or image scanning must be present and enforcing after build output exists.
Evidence:
Dependency scan, filesystem scan, artifact scan, or container image scan job such as `dependency-check`, `trivy fs`, `grype`, `trivy image`, `snyk test`, or `snyk container`.

4. Deployment to a non-production test environment should run automatically after quality and security gates pass.
Evidence:
Deployment-like command plus environment name matching `test`, `qa`, `stage`, `staging`, `dev`, `sandbox`, `review`, or `uat`.

5. Downstream pipelines count toward SSDLC coverage when they can be resolved locally.
Evidence:
`trigger: include: - local: ...` and nested local child pipelines.

### Security Policy Rules

1. Do not use container images with the `latest` tag.
2. Do not use unpinned images without an explicit version or digest.
3. Do not set `allow_failure: true` on critical quality or security jobs.
4. Do not disable SSH host verification with `StrictHostKeyChecking no`.
5. Do not keep inline secrets in top-level `variables`.
6. Do not pipe downloaded remote scripts directly into `sh` or `bash`.

### Maintainability Rules

1. Prefer `workflow` governance over job-only execution rules.
2. Avoid duplicate script blocks; refactor through `extends`, anchors, or hidden jobs.
3. Keep rule expressions readable and below a reasonable complexity threshold.
4. Avoid deprecated `only/except` where `rules` is more explicit.
5. Keep job stage usage aligned with the declared stage list.
6. Limit unnecessary global variables.
7. Track unresolved downstream references as an analysis-quality risk.

## Recommended Next Rules

### SSDLC Expansion

1. Enforce coverage publication separately from mere unit-test execution.
2. Detect DAST presence for services that expose HTTP endpoints.
3. Require SBOM generation for build outputs.
4. Verify that production deployment is gated by earlier security stages.
5. Recognize secret-detection and IaC scanning as first-class controls.

### Security Expansion

1. Flag curl or wget downloads unless a checksum or signature verification step exists.
2. Flag remote includes that are not pinned to a version, ref, or digest.
3. Require short-lived credentials such as OIDC or Vault over static secrets.
4. Detect use of privileged containers, Docker-in-Docker, or unsafe runner settings.
5. Detect public artifact exposure or overly broad retention settings.

### Governance Expansion

1. Require merge request coverage for all business-supported branches.
2. Require protected branch rules for release and production flows.
3. Require approval or manual promotion only for production, not test, environments.
4. Flag child pipelines that bypass the same quality gates as the parent pipeline.
5. Detect branching strategies that unintentionally avoid security jobs.

## Scoring Guidance

- Missing mandatory SSDLC controls should remain high-impact scoring events.
- Security policy violations should produce explicit findings with remediation text.
- Maintainability findings should affect score, but less aggressively than missing core SSDLC gates.
- Partial downstream visibility should reduce confidence and be reported clearly.

## Rule Authoring Standard

Every rule should define:

- what it detects
- why it matters
- what evidence is accepted
- what severity it carries
- what recommendation the tool should show
- what concrete remediation text the tool should provide
