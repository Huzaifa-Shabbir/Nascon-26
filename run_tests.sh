#!/usr/bin/env bash
# Runs all unit tests with per-module line coverage.
# Usage: ./run_tests.sh   (needs: pip install -r backend/requirements-dev.txt)
set -euo pipefail
cd "$(dirname "$0")"
python -m pytest tests --cov=backend/app --cov-report=term-missing "$@"
