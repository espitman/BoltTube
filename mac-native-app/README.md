# BoltTube macOS App

This folder now supports a real macOS app workflow like a standard Xcode project.

## Open in Xcode

- Open [`/Users/espitman/Documents/Projects/BoltTube/mac-native-app/BoltTube.xcodeproj`](/Users/espitman/Documents/Projects/BoltTube/mac-native-app/BoltTube.xcodeproj)
- Build and run the `BoltTube` scheme

## Build a `.app` from terminal

```bash
cd /Users/espitman/Documents/Projects/BoltTube/mac-native-app
./Scripts/build-app.sh
```

Release output:

```text
build/Build/Products/Release/BoltTube.app
```

You can drag `BoltTube.app` into `Applications`.
