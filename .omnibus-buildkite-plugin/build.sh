#!/bin/bash
set -ueo pipefail

DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"

# source the build settings
. ./.omnibus-buildkite-plugin/build-settings.sh

if [[ ! -f "$CONFIG" ]]; then
  echo "Could not complete build -- $CONFIG file does not exist!"
  exit 1
fi

config_dir="$(dirname $CONFIG)"
config_file="${CONFIG##*/}"

echo "--- Deleting Omnibus cache"
sudo rm -rf /var/cache/omnibus
sudo mkdir -p /var/cache/omnibus
sudo chown "$(id -u -n)" /var/cache/omnibus

echo "--- Deleting Omnibus project install directory"
sudo rm -rf "$INSTALL_DIR"
sudo mkdir "$INSTALL_DIR"
sudo chown "$(id -u -n)" "$INSTALL_DIR"

echo "--- Setting Omnibus build environment variables"
. /usr/local/bin/load-omnibus-toolchain.sh

# The key used to sign RPM packages is passphrase-less
export OMNIBUS_RPM_SIGNING_PASSPHRASE=''

BUILD_OPTIONS="--config $config_file $BUILD_OPTIONS"

pushd "$config_dir"

echo "--- Building ${PROJECT_NAME}"
bundle install --without development
bundle exec omnibus build "$PROJECT_NAME" $BUILD_OPTIONS

popd

echo "--- Publishing ${PROJECT_NAME} packages to omnibus-unstable-local"
ruby "$DIR/publish.rb"

ruby -r json -e "File.write('LAST_BUILD_VERSION', JSON.parse(File.read(Dir.glob('**/pkg/*.metadata.json').first))['version'], { mode: 'w', encoding: 'UTF-8'})"
