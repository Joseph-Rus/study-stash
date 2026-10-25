# Study Stash for iPhone and iPad

The native app (SwiftUI, iOS 26+). It reads the library on the student's laptop through their own Google Drive
(Continue with Google, `docs/phone-google.md`), or, like the phone web app in `web/`, over Tailscale through
`/api/v2`. Everything still runs on the computer.

## Build

```sh
brew install xcodegen
cd ios
xcodegen generate          # StudyStash.xcodeproj from project.yml
open StudyStash.xcodeproj  # or:
xcodebuild -scheme StudyStash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Connecting

Over Google: on the laptop, Settings → Phone → **Connect with Google**; on the phone, **Continue with Google** with the
same account (or scan the laptop's QR code, `studystash://google?account=…`). The iOS client's id goes in
`project.yml` (`GOOGLE_IOS_CLIENT_ID` and its reversed form `GOOGLE_IOS_URL_SCHEME`); until then it's a placeholder
and Continue with Google says it isn't set up.

Over Tailscale (Other ways): in Study Stash on the computer, Settings → Phone → **Add a phone**. The app scans that QR
code (or takes the address typed in), then the 6-digit code.

In the simulator there's no camera. A debug build takes launch arguments instead:

- `-pair <address> <code>` pairs on launch
- `-tab due|ask|settings|search` opens a tab
- `-open lecture:<id>` or `-open class:<name>` opens a screen
- `-ask "<question>"` asks it on the Ask tab
- `-drive-token-file <path> -drive-space <prefix>` connects over Google Drive with a test account's token (a JSON with
  `client_id`, `client_secret`, `token_uri`, `refresh_token`), every file in the folder named `<prefix>…`; no one
  presses Allow. Never a real student's account, and delete the prefix's files after.
