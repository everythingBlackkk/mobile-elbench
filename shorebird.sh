#!/usr/bin/env bash
# Android store releases and over-the-air patches through Shorebird.
#
#   ./shorebird.sh release android   build the binary you upload to Google Play
#   ./shorebird.sh patch android     send a Dart/UI change to Android phones running that release
#   ./shorebird.sh preview android   install a release with its latest patch on an Android device
#
# iOS uses standard Flutter builds without Shorebird.
# Patches cannot change Kotlin, native plugins, AndroidManifest or assets; those need a new release.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$project_dir"
export PATH="$HOME/.shorebird/bin:$PATH"

# Patches must be built with the same Flutter as the release they update.
flutter_version=3.44.2
# Keep every Material icon in the release, so a patch can use icons the release did not.
build_args=(--no-tree-shake-icons)
# Releases accept only patches signed with this key pair. The private key never leaves this Mac.
keys="${SHOREBIRD_KEYS:-$HOME/Documents/secret-app/shorebird}"

action="${1:-}"
platform="${2:-}"
require_android() {
  [[ "$platform" == android ]] || {
    echo "Shorebird is enabled only for Android. Build and install iOS with the standard Flutter SDK." >&2
    echo "Usage: $0 $action android" >&2
    exit 1
  }
  command -v shorebird >/dev/null || { echo 'Install Shorebird: https://docs.shorebird.dev' >&2; exit 1; }
}

case "$action" in
  release|patch)
    require_android
    [[ -f shorebird.yaml ]] || { echo 'Run "shorebird login" and then "shorebird init" first.' >&2; exit 1; }
    [[ -f "$keys/public.pem" ]] || { echo "Missing $keys/public.pem (patch signing key)." >&2; exit 1; }
    extra=(--public-key-path="$keys/public.pem")
    [[ "$action" == release ]] && extra+=(--flutter-version="$flutter_version")
    if [[ "$action" == patch ]]; then
      [[ -f "$keys/private.pem" ]] || { echo "Missing $keys/private.pem (patch signing key)." >&2; exit 1; }
      extra+=(--private-key-path="$keys/private.pem")
    fi
    shorebird "$action" "$platform" "${extra[@]}" "${@:3}" -- "${build_args[@]}"
    ;;
  preview)
    require_android
    shorebird preview "${@:3}" --platform=android
    ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
