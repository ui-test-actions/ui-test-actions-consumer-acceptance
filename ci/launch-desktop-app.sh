#!/usr/bin/env bash
set -euo pipefail
fixture_python=python
if [[ "$RUNNER_OS" == Linux ]]; then fixture_python=/usr/bin/python3; fi
"$fixture_python" fixtures/desktop.py fixture-ready > fixture.log 2>&1 &
