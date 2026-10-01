#!/usr/bin/env bash
# Unit tests: every XCTest class except *IntegrationTest.
cd "$(dirname "$0")/.."
source ./script/setup.sh

swift test --skip IntegrationTest
