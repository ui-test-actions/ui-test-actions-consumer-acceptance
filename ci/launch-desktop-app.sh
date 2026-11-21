#!/usr/bin/env bash
set -euo pipefail
if [[ "${CONSUMER_SCENARIO:-}" == v301-native-freeze ]]; then
    touch fixture-ready
    exit
fi
fixture_python=python
if [[ "$RUNNER_OS" == Linux ]]; then fixture_python=/usr/bin/python3; fi
"$fixture_python" fixtures/desktop.py fixture-ready > fixture.log 2>&1 &
if [[ "${CONSUMER_SCENARIO:-}" == v301-connector-exit ]]; then
    bash ci/stop-quick-connector.sh >"$RUNNER_TEMP/connector-fault.log" 2>&1 &
fi
