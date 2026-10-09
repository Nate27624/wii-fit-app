# Weight Tracker

Native iOS app for recording body weight in pounds and plotting entries over time.

## Requirements

- Xcode 26.2 or newer
- XcodeGen

## Generate

```bash
xcodegen generate
```

## Test

```bash
xcodebuild test -project WeightTracker.xcodeproj -scheme WeightTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```
