# Release Guide

This repository already contains a release workflow in [`.github/workflows/release.yml`](/Users/polishyankee/Desktop/Devops-1/projects/gitlab-ci-ssdlc-auditor/.github/workflows/release.yml). A release cut mainly requires repository settings, a version tag, and one local verification pass.

## Release Checklist

Before cutting a public release, verify these GitHub settings:

1. In `Settings -> Actions -> General -> Workflow permissions`, set `Read and write permissions`.
2. In `Settings -> Actions -> General`, allow workflows to create releases and publish packages through `GITHUB_TOKEN`.
3. In `Packages`, keep GitHub Container Registry enabled for the repository owner.
4. If you want the image to be public immediately, set the GHCR package visibility to `Public` after the first push.

The release workflow publishes:

- a GitHub Release
- generated example reports as release assets
- a multi-arch container image to `ghcr.io/polishyankee/gitlab-ci-auditor`

## Local Release Preparation

Use the helper script to run the unit tests, build a versioned Docker image locally, and smoke-test the CLI image before tagging:

```bash
./scripts/prepare_release.sh v0.3.0
```

The script builds:

- `gitlab-ci-auditor:v0.3.0`
- `ghcr.io/polishyankee/gitlab-ci-auditor:v0.3.0`

It also smoke-tests the image with:

```bash
docker run --rm gitlab-ci-auditor:v0.3.0 scan /app/examples/pipelines/compliant_service.gitlab-ci.yml
```

## Cut The Release

After the local checks pass:

```bash
git tag v0.3.0
git push origin v0.3.0
```

That tag triggers the `Release` workflow automatically.

You can also trigger the workflow manually in GitHub:

1. Open `Actions -> Release`.
2. Click `Run workflow`.
3. Provide the version string, for example `v0.3.0`.

## Post-Release Verification

After GitHub Actions completes, verify:

1. The GitHub Release exists and contains generated example reports.
2. The GHCR image exists for:
   `ghcr.io/polishyankee/gitlab-ci-auditor:v0.3.0`
3. The `latest` tag was updated.
4. Pull and run the image:

```bash
docker pull ghcr.io/polishyankee/gitlab-ci-auditor:v0.3.0
docker run --rm ghcr.io/polishyankee/gitlab-ci-auditor:v0.3.0 scan /app/examples/pipelines/compliant_service.gitlab-ci.yml
```

## Notes

- Local Docker verification requires a running Docker daemon.
- The release workflow itself performs the real multi-arch publish to GHCR.
- If you want reproducible versioning, keep semantic tags only in the `vX.Y.Z` format.
