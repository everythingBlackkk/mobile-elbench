#!/usr/bin/env bash
# Store releases and over-the-air patches through Shorebird.
#
#   ./shorebird.sh release android|ios   build the binary you upload to Google Play / the App Store
#   ./shorebird.sh patch android|ios     send a Dart/UI change to phones already running that release
#   ./shorebird.sh preview               install a release with its latest patch on a connected device
#
# Patches can change any Dart code (screens, layout, colours, texts, logic). They cannot change Swift/Kotlin,
# plugins with native code, Info.plist/AndroidManifest, or files under assets/ — those need a new store release.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$project_dir"
export PATH="$HOME/.shorebird/bin:$PATH"
command -v shorebird >/dev/null || { echo 'Install Shorebird: https://docs.shorebird.dev' >&2; exit 1; }

# Patches must be built with the same Flutter as the release they update.
flutter_version=3.44.2
# Keep every Material icon in the release, so a patch can use icons the release did not.
build_args=(--no-tree-shake-icons)
# Releases accept only patches signed with this key pair. The private key never leaves this Mac.
keys="${SHOREBIRD_KEYS:-$HOME/Documents/secret-app/shorebird}"

action="${1:-}"
platform="${2:-}"
case "$action" in
  release|patch)
    [[ "$platform" == android || "$platform" == ios ]] || { echo "Usage: $0 $action android|ios" >&2; exit 1; }
    [[ -f shorebird.yaml ]] || { echo 'Run "shorebird login" and then "shorebird init" first.' >&2; exit 1; }
    [[ -f "$keys/public.pem" ]] || { echo "Missing $keys/public.pem (patch signing key)." >&2; exit 1; }
    extra=(--public-key-path="$keys/public.pem")
    [[ "$action" == release ]] && extra+=(--flutter-version="$flutter_version")
    if [[ "$action" == patch ]]; then
      [[ -f "$keys/private.pem" ]] || { echo "Missing $keys/private.pem (patch signing key)." >&2; exit 1; }
      extra+=(--private-key-path="$keys/private.pem")
    fi
    # iOS patches must say which release they update; Shorebird asks when there is more than one.
    shorebird "$action" "$platform" "${extra[@]}" "${@:3}" -- "${build_args[@]}"
    ;;
  preview)
    shorebird preview "${@:2}"
    ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
