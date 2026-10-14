# strata-menubar

A small macOS menu bar app that starts and stops a locally installed
[Strata](https://github.com/Niko1221/Strata) server (Qwen3.8-Flash-Next Q2_0).

## Requirements

- macOS 15 or newer on Apple Silicon
- Xcode 16 or newer (Xcode 27 was used)

## Build and test

```sh
xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StrataMenubar.xcodeproj -scheme StrataMenubar -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

The app is built into `.build/DerivedData/Build/Products/Debug/StrataMenubar.app`.
No Apple developer account is needed; the binary is ad-hoc signed.
