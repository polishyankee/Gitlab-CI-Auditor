#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/prepare_release.sh vX.Y.Z

Runs the unit tests, builds a release-ready Docker image locally, and smoke-tests
the image against a built-in example pipeline before you push a release tag.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

VERSION="$1"

if [[ ! "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a semantic version tag such as v0.1.0, got: ${VERSION}" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI is required to prepare a release image." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not available. Start Docker and rerun the release preparation." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse HEAD)"
LOCAL_IMAGE="gitlab-ci-auditor:${VERSION}"
GHCR_IMAGE="ghcr.io/polishyankee/gitlab-ci-auditor:${VERSION}"

echo "==> Running unit tests"
ruby -I lib:test test/run_all.rb

echo "==> Building Docker image ${LOCAL_IMAGE}"
docker build --pull \
  --build-arg VERSION="${VERSION}" \
  --build-arg BUILD_DATE="${BUILD_DATE}" \
  --build-arg VCS_REF="${VCS_REF}" \
  -t "${LOCAL_IMAGE}" \
  -t "${GHCR_IMAGE}" \
  .

echo "==> Smoke testing CLI image"
docker run --rm "${LOCAL_IMAGE}" scan /app/examples/pipelines/compliant_service.gitlab-ci.yml >/dev/null

echo
echo "Local release preparation finished."
echo "Built images:"
echo "  - ${LOCAL_IMAGE}"
echo "  - ${GHCR_IMAGE}"
echo
echo "Next step:"
echo "  git tag ${VERSION}"
echo "  git push origin ${VERSION}"
