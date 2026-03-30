#!/usr/bin/env sh
set -eu

trivy fs --scanners vuln,license --format cyclonedx --output sbom.cyclonedx.json .
trivy fs --format json --output gl-dependency-scanning-report.json .

