#!/bin/sh
# One-time Android platform scaffolding for the OPPA Flutter app.
#
# The repository intentionally does NOT commit apps/mobile/android — Flutter
# regenerates it, and committing it pins per-machine Gradle/AGP state. Run this
# script once in any environment that has the Flutter SDK, then build:
#
#   sh ./scripts/prepare_android.sh
#   cd apps/mobile && flutter build apk --debug --dart-define=OPPA_DEMO_MODE=true
#
# `flutter create` on an existing project only adds missing platform folders;
# it does not touch lib/, test/ or pubspec.yaml.
set -eu

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter is not on PATH. Install the Flutter SDK first." >&2
  exit 1
fi

flutter config --enable-android

cd apps/mobile
flutter create --platforms=android --org gg.oppa --project-name oppa_mobile .
echo "Android platform ready. Next:"
echo "  cd apps/mobile && flutter build apk --debug --dart-define=OPPA_DEMO_MODE=true"
