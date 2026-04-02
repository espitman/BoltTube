# Development Rules

## Mac Native App Logic
- After making any changes to the Mac application code (Swift, Python resources, etc.), you **MUST** rebuild and restart the application using `xcodebuild` and ensure it has successfully launched.
- Always check that the app bundle path before running `open`.
- Ensure the bridge server starts correctly if the Mac app is active.

## Android TV Logic
- When building a release APK, ensure the output is copied to the user's Desktop with a clear name.
