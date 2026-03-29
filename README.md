# GitLab CI SSDLC Auditor

Self-contained tool for evaluating `.gitlab-ci.yml` quality against SSDLC expectations, security policies, and long-term maintainability. The analysis engine is stdlib-first and easy to extend. The optional GUI server uses `webrick` on modern Ruby releases.

## What It Checks

- unit test execution
- coverage reporting
- SAST coverage
- artifact scanning or image scanning
- automated deployment to a test environment
- baseline security policy compliance
- pipeline complexity and maintainability
- active execution paths derived from `workflow`, `rules`, `rules:changes`, `only/except`, branches, and tags

## Scan Scope

The auditor evaluates the full local pipeline graph, not just the root file:

- recursively expands local `include`
- scans child/downstream pipelines started by `trigger: include: - local: ...`
- follows nested local child pipelines as long as the referenced files are available locally
- can import external or artifact-based downstream pipelines through local YAML snapshot manifests

If a downstream pipeline depends on `project`, `artifact`, `template`, or another external mechanism, the report marks the analysis as partial and explains the gap with remediation guidance.

## Unit Test Heuristics

The unit-test control is considered satisfied not only by a dedicated test job, but also when:

- a Maven job runs `mvn test|verify|package|install|deploy` or `./mvnw ...` without `-DskipTests` and without `-Dmaven.test.skip`
- a Gradle job runs `gradle` or `./gradlew` with `test|build|check` without `-x test` and without `--exclude-task test`
- `artifacts` contains JaCoCo evidence such as `jacoco.exec` or `jacoco.xml`

Coverage reporting is tracked separately from plain test execution. The auditor recognizes common artifacts such as JaCoCo, Cobertura, and LCOV outputs.

## SAST Heuristics

The SAST control recognizes both GitLab SAST templates and common stack-specific scanners. The current heuristics cover:

- Java: `spotbugs`, `findsecbugs`, `sonar-scanner`, `semgrep`, `codeql`
- .NET: `dotnet sonarscanner`, `SonarScanner.MSBuild.exe`, `Security Code Scan`, `semgrep`, `snyk code test`
- Node / JS: `semgrep`, `njsscan`, `nodejsscan`, `sonar-scanner`, `snyk code test`
- Python: `bandit`, `semgrep`, `codeql`
- Go: `gosec`, `semgrep`, `codeql`
- Ruby: `brakeman`, `semgrep`, `codeql`
- PHP: `psalm --taint-analysis`, `progpilot`, `semgrep`, `codeql`

When SAST is missing, remediation guidance is adapted to the stacks detected from the pipeline definition.

## Run

CLI:

```bash
chmod +x ./bin/gitlab-ci-auditor
./bin/gitlab-ci-auditor scan .gitlab-ci.yml
```

List bundled policy packs:

```bash
./bin/gitlab-ci-auditor list-packs
```

HTML report:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --format html --output report.html
```

CSV export:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --format csv --output report.csv
```

PDF export:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --format pdf --output report.pdf
```

JSON bundle export:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --format json-bundle --output report.bundle.json
```

GUI:

```bash
gem install webrick
./bin/gitlab-ci-auditor serve --host 127.0.0.1 --port 4567
```

If you only use `scan` and report export modes, `webrick` is not required.

## Docker

Build the image:

```bash
docker build --pull -t gitlab-ci-ssdlc-auditor .
```

Run a scan against a pipeline from your current repository:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace:ro" \
  gitlab-ci-ssdlc-auditor \
  scan /workspace/.gitlab-ci.yml
```

Write an HTML report back to the host:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace" \
  gitlab-ci-ssdlc-auditor \
  scan /workspace/.gitlab-ci.yml --format html --output /workspace/report.html
```

Run the GUI in Docker:

```bash
docker run --rm \
  -p 4567:4567 \
  -v "$PWD:/workspace:ro" \
  gitlab-ci-ssdlc-auditor \
  serve --host 0.0.0.0 --port 4567
```

Scan one of the built-in example pipelines without mounting anything:

```bash
docker run --rm gitlab-ci-ssdlc-auditor scan /app/examples/pipelines/compliant_service.gitlab-ci.yml
```

Use a bundled policy pack and downstream snapshots from a mounted repository:

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace" \
  gitlab-ci-ssdlc-auditor \
  scan /workspace/.gitlab-ci.yml --policy-pack strict --snapshot-file /workspace/.gitlab-ci-downstream-snapshots.json
```

Pull the published release image from GitHub Container Registry:

```bash
docker pull ghcr.io/polishyankee/gitlab-ci-auditor:latest
```

The image runs as a non-root user by default and exposes the GUI on port `4567`.

## Policies

Bundled policy packs live in [`config/policies`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/config/policies). The current packs are:

- `balanced`: full SSDLC baseline for most application repositories
- `strict`: balanced baseline plus stricter image hygiene and remote script execution controls
- `library`: disables automated test deployment for repositories that build shared libraries or components rather than deployable services

Use a bundled pack:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --policy-pack strict
```

Use imported downstream snapshots:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --snapshot-file .gitlab-ci-downstream-snapshots.json
```

Or provide a custom JSON policy file:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --policy ./my-policy.json
```

## Unit Tests

Run the full application test suite with:

```bash
ruby -I lib:test test/run_all.rb
```

The suite includes direct tests for expression evaluation, policy loading, rule matching, pipeline loading, report rendering, integration scenarios, and example smoke coverage.

## Examples

Ready-made sample pipelines and reference reports live in [`examples/README.md`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/README.md).

Included examples:

- compliant service pipeline
- library package pipeline for the `library` pack
- intentionally weak legacy pipeline
- snapshot-backed downstream pipeline

Regenerate the example reports with:

```bash
./scripts/generate_example_reports.sh
```

## GitHub Actions and Releases

The repository includes GitHub Actions workflows for:

- running the Ruby test suite on pushes and pull requests
- building the Docker image on every push, pull request, and manual CI run
- smoke-testing both the CLI and GUI container flows in CI
- publishing a GitHub release and a multi-arch GHCR container image on version tags such as `v0.3.0`
- attaching generated example reports to each GitHub release

The repository also includes a [`Dependabot`](.github/dependabot.yml) configuration for GitHub Actions and Docker base image updates.

The published image target is:

```bash
ghcr.io/polishyankee/gitlab-ci-auditor
```

To cut a release manually after pushing the workflow changes, create and push a version tag:

```bash
git tag v0.3.0
git push origin v0.3.0
```

Or trigger the `Release` workflow manually in GitHub and provide the version tag as input. The workflow uses that value as the release tag and publishes the same version to GHCR.

## Contribution Flow

Repository changes should go through pull requests rather than direct pushes to `main`.

Recommended flow:

1. Create a branch from `main`.
2. Implement one focused change.
3. Run `ruby -I lib:test test/run_all.rb`.
4. Open a pull request with the provided template.
5. Merge only after CI passes and review comments are closed.

The repository includes [`.github/pull_request_template.md`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/.github/pull_request_template.md) and [`.github/CODEOWNERS`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/.github/CODEOWNERS) to support that workflow.

## Designed For Growth

This repository is intended to keep evolving. The core extension points are:

- `config/policies/*.json` for bundled policy packs
- [`RULES.md`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/RULES.md) for the proposed rule catalog
- [`BACKLOG.md`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/BACKLOG.md) for the implementation backlog derived from the rule catalog
- [`ROADMAP.md`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/ROADMAP.md) for planned capabilities
- [`CONTRIBUTING.md`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/CONTRIBUTING.md) for contribution and rule-authoring guidance

## Current Limitations

- `rules` and `workflow` analysis is static, so the tool builds a set of detectable scenarios instead of executing GitLab's full runtime semantics
- local `include` and local child/downstream pipelines are expanded, but `remote/project/template/artifact` references are only assessed partially
- GitLab templates influence scoring by inference only because the tool does not fetch remote template contents
