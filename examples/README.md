# Example Pipelines and Reports

This directory contains ready-to-scan `.gitlab-ci.yml` examples that illustrate both strong and weak SSDLC implementations.

## Pipelines

- [`pipelines/compliant_service.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/compliant_service.gitlab-ci.yml): fully compliant service pipeline for the `balanced` policy pack
- [`pipelines/library_package.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/library_package.gitlab-ci.yml): library-oriented pipeline that passes the `library` policy pack without a test deployment step
- [`pipelines/legacy_monolith.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/legacy_monolith.gitlab-ci.yml): intentionally weak pipeline with SSDLC and security gaps
- [`pipelines/snapshot_root.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/snapshot_root.gitlab-ci.yml): root pipeline that imports an external child pipeline through a local snapshot manifest
- [`pipelines/argocd_release_root.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/argocd_release_root.gitlab-ci.yml): example that combines SonarQube, a script-backed `trivy fs` dependency scan, and a deployment executed from an external ArgoCD repository snapshot
- [`pipelines/samm_question_rich.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/samm_question_rich.gitlab-ci.yml): implementation-heavy example with richer OWASP SAMM question coverage
- [`pipelines/samm_question_gaps.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/samm_question_gaps.gitlab-ci.yml): intentionally weak example that leaves many OWASP SAMM implementation questions on `fail` or `review`
- [`pipelines/upload_bundle_demo/.gitlab-ci.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/pipelines/upload_bundle_demo/.gitlab-ci.yml): nested local-include example meant to validate GUI ZIP upload, directory upload, and root-plus-support-file upload flows

## Generated Reports

- [`reports/compliant_service.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/compliant_service.html)
- [`reports/compliant_service.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/compliant_service.txt)
- [`reports/library_package.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/library_package.html)
- [`reports/library_package.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/library_package.txt)
- [`reports/legacy_monolith.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/legacy_monolith.html)
- [`reports/legacy_monolith.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/legacy_monolith.txt)
- [`reports/snapshot_root.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/snapshot_root.html)
- [`reports/snapshot_root.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/snapshot_root.txt)
- [`reports/argocd_release_root.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/argocd_release_root.html)
- [`reports/argocd_release_root.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/argocd_release_root.txt)
- [`reports/samm_question_rich.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/samm_question_rich.html)
- [`reports/samm_question_rich.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/samm_question_rich.txt)
- [`reports/samm_question_gaps.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/samm_question_gaps.html)
- [`reports/samm_question_gaps.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/samm_question_gaps.txt)
- [`reports/upload_bundle_demo.html`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/upload_bundle_demo.html)
- [`reports/upload_bundle_demo.txt`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/examples/reports/upload_bundle_demo.txt)

## Regenerate

Run:

```bash
./scripts/generate_example_reports.sh
```

The script regenerates the example text and HTML reports from the current analyzer implementation.
