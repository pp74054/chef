#!/bin/bash
set -ueo pipefail

DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

# source the build settings
. ./.omnibus-buildkite-plugin/build-settings.sh

echo "--- Setting Omnibus build environment variables"
. /usr/local/bin/load-omnibus-toolchain.sh

echo "--- Publishing ${PROJECT_NAME} packages to omnibus-unstable-local"
ruby "$DIR/publish.rb"
