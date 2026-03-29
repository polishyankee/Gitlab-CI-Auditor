# Contributing

This repository is meant to keep growing. New rules, policy packs, graph features, and report capabilities should be added in a way that keeps the auditor deterministic and easy to review.

## Development Workflow

All changes should go through a pull request.

1. Create a short-lived branch from `main`.
2. Keep the branch focused on one problem or one logical improvement.
3. Add or update tests together with the implementation.
4. Open a pull request instead of pushing directly to `main`.
5. Merge only after CI passes and the review comments are resolved.

Recommended branch prefixes:

- `feature/` for new capabilities
- `fix/` for bug fixes
- `chore/` for repository maintenance
- `docs/` for documentation-only changes

Recommended pull request scope:

- one rule family
- one UI/report improvement
- one CI or Docker change
- one bug fix with its regression test

Direct pushes to `main` should be avoided. The repository should treat `main` as the protected integration branch.

## Core Principles

- Prefer static analysis over implicit guesswork.
- Keep every new heuristic backed by a fixture and an automated test.
- Separate detection, scoring, and presentation concerns.
- Preserve explainability: every finding must describe the issue, the recommendation, and how to fix it.

## Project Structure

- `lib/gitlab_ci_auditor/pipeline_loader.rb`: loads root, local includes, and local child or downstream pipelines.
- `lib/gitlab_ci_auditor/rule_evaluator.rb`: evaluates `workflow`, `rules`, and `only/except`.
- `lib/gitlab_ci_auditor/analyzer.rb`: classifies jobs, scores controls, builds findings, and prepares graph data.
- `lib/gitlab_ci_auditor/report_renderer.rb`: text and HTML rendering.
- `templates/`: GUI and HTML report templates.
- `config/default_policy.json`: default supported policy switches.
- `test/fixtures/`: sample pipelines used by automated tests.

## Adding a New Rule

1. Decide whether the rule is:
   - a control rule affecting SSDLC scoring
   - a security policy rule producing a policy finding
   - a maintainability rule affecting maintainability scoring
2. Add or extend detection logic in `lib/gitlab_ci_auditor/analyzer.rb`.
3. Add at least one positive and one negative fixture under `test/fixtures/`.
4. Extend `test/test_gitlab_ci_auditor.rb` with a regression test.
5. Update `RULES.md` so the rule catalog stays aligned with the implementation.

## Adding Policy Pack Options

- Keep policy switches explicit and JSON-serializable.
- Add a safe default in `config/default_policy.json`.
- If a policy is advisory rather than mandatory, model that clearly in scoring or findings rather than hiding it in one generic severity.

## Report UX Expectations

- Keep all user-facing text in English.
- Findings must remain actionable, not just descriptive.
- Graph nodes should expose both strengths and weak spots where possible.
- Avoid adding UI-only logic that duplicates analysis logic already available in Ruby.

## Verification

Run the local test suite with:

```bash
ruby -I lib:test test/run_all.rb
```

Run a manual scan with:

```bash
./bin/gitlab-ci-auditor scan .gitlab-ci.yml
./bin/gitlab-ci-auditor scan .gitlab-ci.yml --format html --output report.html
```

If you want to validate the Docker image locally, run:

```bash
docker build --pull -t gitlab-ci-ssdlc-auditor .
docker run --rm gitlab-ci-ssdlc-auditor scan /app/examples/pipelines/compliant_service.gitlab-ci.yml
```

## Pull Request Expectations

Every pull request should explain:

- what changed
- why the change was needed
- how it was verified
- whether the rule model, policy packs, or report output changed

If the change affects scoring, findings, or scenario generation, include fixture updates and mention the expected user-facing impact in the PR description.

## Recommended GitHub Settings

These settings are not enforced by files in the repository and should be enabled in GitHub repository settings:

- protect `main`
- require pull requests before merging
- require at least one approval
- require status checks from `CI`
- dismiss stale approvals when new commits are pushed
- restrict force pushes to `main`
