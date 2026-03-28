# GitLab CI SSDLC Auditor

Self-contained tool for evaluating `.gitlab-ci.yml` quality against SSDLC expectations, security policies, and long-term maintainability. It uses only the Ruby standard library and is designed to stay easy to extend.

## What It Checks

- unit test execution
- SAST coverage
- artifact scanning or image scanning
- automated deployment to a test environment
- baseline security policy compliance
- pipeline complexity and maintainability
- active execution paths derived from `workflow`, `rules`, `only/except`, branches, and tags

## Scan Scope

The auditor evaluates the full local pipeline graph, not just the root file:

- recursively expands local `include`
- scans child/downstream pipelines started by `trigger: include: - local: ...`
- follows nested local child pipelines as long as the referenced files are available locally

If a downstream pipeline depends on `project`, `artifact`, `template`, or another external mechanism, the report marks the analysis as partial and explains the gap with remediation guidance.

## Unit Test Heuristics

The unit-test control is considered satisfied not only by a dedicated test job, but also when:

- a Maven job runs `mvn test|verify|package|install|deploy` or `./mvnw ...` without `-DskipTests` and without `-Dmaven.test.skip`
- a Gradle job runs `gradle` or `./gradlew` with `test|build|check` without `-x test` and without `--exclude-task test`
- `artifacts` contains JaCoCo evidence such as `jacoco.exec` or `jacoco.xml`

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

GUI:

```bash
./bin/gitlab-ci-auditor serve --host 127.0.0.1 --port 4567
```

## Policies

Bundled policy packs live in [`config/policies`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/config/policies). The current packs are:

- `balanced`: full SSDLC baseline for most application repositories
- `strict`: balanced baseline plus stricter image hygiene and remote script execution controls
- `library`: disables automated test deployment for repositories that build shared libraries or components rather than deployable services

Use a bundled pack:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --policy-pack strict
```

Or provide a custom JSON policy file:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --policy ./my-policy.json
```

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
