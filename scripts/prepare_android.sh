#!/bin/sh
# Android platform scaffolding for the OPPA Flutter app (fallback tool).
#
# apps/mobile/android IS COMMITTED (CI builds directly from the checkout).
# This script exists to regenerate the platform folder if it is ever removed,
# or to add a new platform (ios/ later):
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
