# BoltTube

This repository contains:

- `android-phone-app`: the Android client
- `mac-native-app`: the native macOS app

## Android Local AAR Files

Two large legacy AAR files are intentionally ignored:

- `android-phone-app/libs/ffmpeg-0.18.1.aar`
- `android-phone-app/libs/library-0.18.1.aar`

They are not required by the current Android build. The current app uses `androidx.media3` from Maven dependencies in [`android-phone-app/build.gradle.kts`](/Users/espitman/Documents/Projects/BoltTube/android-phone-app/build.gradle.kts).

If you ever need to restore the old local-AAR-based setup, place those files manually in:

- `android-phone-app/libs/`

Source of those files:

- use the original BoltTube/private project artifacts they came from
- or export them from the older local Android setup that previously used these AARs

They are not published or resolved automatically by this repository.
