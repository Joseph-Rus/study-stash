# Releasing the iPhone and iPad app

## Once

1. **Xcode → Settings → Accounts**: sign in with the Apple ID on the developer team (6K4VZU48G9).
2. **App Store Connect → Apps → +, New App**: iOS, name *Study Stash*, bundle ID `app.studystash.ios` (run
   `ios/release.sh --local` once first if it isn't in the list yet: that registers it), SKU `studystash-ios`.
3. **App Privacy**: "Data Not Collected". The app talks only to the student's own library, on their own computer,
   and `PrivacyInfo.xcprivacy` says so.

## Each build

```sh
ios/release.sh
```

It archives, signs and uploads. Then in App Store Connect → TestFlight:

- **Internal testing**: add yourself (and Joey); the build installs from the TestFlight app straight away.
- **External testing**: make a group, turn on the **public link**, and send it to anyone. The first build of each
  version gets a short Beta App Review (about a day).

## The App Store

Submit a TestFlight build for review with:

- **Sign-in information**: none needed. In *Notes for review*, write: *"Study Stash reads a library on the user's own
  computer. To try it without one, tap **Try a demo** on the first screen: it opens a demo library built into the
  app."*
- **Screenshots**: run the app in the iPhone 17 Pro Max and iPad Pro 13" simulators with the launch argument
  `-demo -quiet` (Xcode → Scheme → Run → Arguments) and take them with ⌘S.
- **Category**: Education. **Age rating**: 4+.
- **Why it allows plain http** (`NSAllowsArbitraryLoads`): the library is on the user's own tailnet, reached at its
  Tailscale IP when Tailscale Serve (https) isn't set up; Tailscale encrypts that traffic itself.
