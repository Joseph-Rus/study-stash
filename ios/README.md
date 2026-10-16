# Study Stash for iPhone and iPad

The native app (SwiftUI, iOS 26+). Like the phone web app in `web/`, it reads the library over Tailscale through
`/api/v2`, and everything still runs on your computer.

## Build

```sh
brew install xcodegen
cd ios
xcodegen generate          # StudyStash.xcodeproj from project.yml
open StudyStash.xcodeproj  # or:
xcodebuild -scheme StudyStash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Pairing

In Study Stash on the computer: Settings → Phone → **Add a phone**. The app scans that QR code (or takes the address
typed in), then the 6-digit code.

In the simulator there's no camera. A debug build takes launch arguments instead:

- `-pair <address> <code>` pairs on launch
- `-tab due|ask|settings|search` opens a tab
- `-open lecture:<id>` or `-open class:<name>` opens a screen
- `-ask "<question>"` asks it on the Ask tab
