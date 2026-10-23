# APP SUBTREE KNOWLEDGE BASE

<!-- Scored 12: Distinct domain (macOS multi-target root, XcodeGen project definition, shared build orchestration) -->

## OVERVIEW
Root container for macOS SwiftUI applications (TeacherApp, StudentApp) sharing the Shared networking and utility module.

## WHERE TO LOOK
| Target / Module | Path | Description |
|---|---|---|
| Project spec | `project.yml` | XcodeGen specification for TeacherApp and StudentApp targets |
| Teacher controller | `TeacherApp/` | Teacher application target (ScreenCaptureKit, H.264 broadcast, device management) |
| Student receiver | `StudentApp/` | Student application target (kiosk lock, input interception, video/audio playback) |
| Shared library | `Shared/` | Common code compiled into both targets (networking, protocols, utilities) |

## CONVENTIONS
- Build definitions are maintained in `project.yml` (XcodeGen), not directly in `.xcodeproj` files. Run `xcodegen generate` after editing.
- Shared code (`Shared/`) is compiled directly into both targets without creating a separate dynamic framework.
- Deployment target is macOS 13.0+; target architecture is arm64 (Apple Silicon).
- Zero third-party Swift dependencies: only native Apple frameworks (SwiftUI, Network, ScreenCaptureKit, VideoToolbox, AVFoundation, CryptoKit).

## ANTI-PATTERNS
- DO NOT manually edit `FocusIn.xcodeproj/project.pbxproj`; edit `project.yml` and regenerate with XcodeGen.
- DO NOT add CocoaPods, Carthage, or SPM packages; keep the native runtime self-contained.
- DO NOT introduce target-specific imports (e.g. `ScreenCaptureKit` or `dlopen` display hacks) into `Shared/`.

## COMMANDS
```bash
# Regenerate Xcode project files from project.yml
cd source/app && xcodegen generate

# Build targets via xcodebuild
xcodebuild -project FocusIn.xcodeproj -scheme TeacherApp -configuration Release build
xcodebuild -project FocusIn.xcodeproj -scheme StudentApp -configuration Release build
```

