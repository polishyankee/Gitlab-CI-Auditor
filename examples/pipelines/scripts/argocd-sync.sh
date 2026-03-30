#!/usr/bin/env sh
set -eu

argocd app sync demo-service-test
argocd app wait demo-service-test --health --timeout 300
