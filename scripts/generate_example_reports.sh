#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/bin/gitlab-ci-auditor"
REPORT_DIR="$ROOT_DIR/examples/reports"
PIPELINE_DIR="$ROOT_DIR/examples/pipelines"

mkdir -p "$REPORT_DIR"

"$BIN" scan "$PIPELINE_DIR/compliant_service.gitlab-ci.yml" --policy-pack balanced --format html --output "$REPORT_DIR/compliant_service.html"
"$BIN" scan "$PIPELINE_DIR/compliant_service.gitlab-ci.yml" --policy-pack balanced --format text --output "$REPORT_DIR/compliant_service.txt"

"$BIN" scan "$PIPELINE_DIR/library_package.gitlab-ci.yml" --policy-pack library --format html --output "$REPORT_DIR/library_package.html"
"$BIN" scan "$PIPELINE_DIR/library_package.gitlab-ci.yml" --policy-pack library --format text --output "$REPORT_DIR/library_package.txt"

"$BIN" scan "$PIPELINE_DIR/legacy_monolith.gitlab-ci.yml" --policy-pack strict --format html --output "$REPORT_DIR/legacy_monolith.html"
"$BIN" scan "$PIPELINE_DIR/legacy_monolith.gitlab-ci.yml" --policy-pack strict --format text --output "$REPORT_DIR/legacy_monolith.txt"

"$BIN" scan "$PIPELINE_DIR/snapshot_root.gitlab-ci.yml" --policy-pack balanced --format html --output "$REPORT_DIR/snapshot_root.html"
"$BIN" scan "$PIPELINE_DIR/snapshot_root.gitlab-ci.yml" --policy-pack balanced --format text --output "$REPORT_DIR/snapshot_root.txt"

"$BIN" scan "$PIPELINE_DIR/argocd_release_root.gitlab-ci.yml" --policy-pack balanced --format html --output "$REPORT_DIR/argocd_release_root.html"
"$BIN" scan "$PIPELINE_DIR/argocd_release_root.gitlab-ci.yml" --policy-pack balanced --format text --output "$REPORT_DIR/argocd_release_root.txt"

"$BIN" scan "$PIPELINE_DIR/samm_question_rich.gitlab-ci.yml" --policy-pack balanced --format html --output "$REPORT_DIR/samm_question_rich.html"
"$BIN" scan "$PIPELINE_DIR/samm_question_rich.gitlab-ci.yml" --policy-pack balanced --format text --output "$REPORT_DIR/samm_question_rich.txt"

"$BIN" scan "$PIPELINE_DIR/samm_question_gaps.gitlab-ci.yml" --policy-pack strict --format html --output "$REPORT_DIR/samm_question_gaps.html"
"$BIN" scan "$PIPELINE_DIR/samm_question_gaps.gitlab-ci.yml" --policy-pack strict --format text --output "$REPORT_DIR/samm_question_gaps.txt"

"$BIN" scan "$PIPELINE_DIR/upload_bundle_demo/.gitlab-ci.yml" --policy-pack balanced --format html --output "$REPORT_DIR/upload_bundle_demo.html"
"$BIN" scan "$PIPELINE_DIR/upload_bundle_demo/.gitlab-ci.yml" --policy-pack balanced --format text --output "$REPORT_DIR/upload_bundle_demo.txt"

"$BIN" scan "$PIPELINE_DIR/multi_project_app.gitlab-ci.yml" --context-file "$PIPELINE_DIR/multi_project_context.json" --policy-pack balanced --format html --output "$REPORT_DIR/multi_project_context.html"
"$BIN" scan "$PIPELINE_DIR/multi_project_app.gitlab-ci.yml" --context-file "$PIPELINE_DIR/multi_project_context.json" --policy-pack balanced --format text --output "$REPORT_DIR/multi_project_context.txt"

HISTORY_FILE="$REPORT_DIR/compliant_service.history.json"
rm -f "$HISTORY_FILE"
"$BIN" scan "$PIPELINE_DIR/compliant_service.gitlab-ci.yml" --policy-pack balanced --history-file "$HISTORY_FILE" --format text --output /tmp/gitlab-ci-auditor-history-primer.txt
"$BIN" scan "$PIPELINE_DIR/compliant_service.gitlab-ci.yml" --policy-pack balanced --history-file "$HISTORY_FILE" --format html --output "$REPORT_DIR/compliant_service_trends.html"
"$BIN" scan "$PIPELINE_DIR/compliant_service.gitlab-ci.yml" --policy-pack balanced --history-file "$HISTORY_FILE" --format text --output "$REPORT_DIR/compliant_service_trends.txt"
