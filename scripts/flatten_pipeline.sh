#!/usr/bin/env sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: ./scripts/flatten_pipeline.sh ROOT_PIPELINE [--snapshot-file FILE] [--output FILE]" >&2
  echo "Example: ./scripts/flatten_pipeline.sh .gitlab-ci.yml --output flat.gitlab-ci.yml" >&2
  exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cli_path="$repo_root/bin/gitlab-ci-auditor"

has_output_flag=0
prev=
for arg in "$@"; do
  if [ "$prev" = "--output" ]; then
    has_output_flag=1
    break
  fi
  prev="$arg"
done

if [ "$has_output_flag" -eq 0 ]; then
  set -- "$@" --output flat.gitlab-ci.yml
fi

ruby "$cli_path" flatten "$@"
