# Releasing the iPhone and iPad app

## Once

1. **Xcode → Settings → Accounts**: sign in with the Apple ID on the developer team (6K4VZU48G9), as Account Holder
   or Admin, so Xcode can make the distribution certificate and profiles itself.
2. **App Store Connect → Apps → +, New App**: iOS, name *Study Stash*, bundle ID `app.studystash.ios` (run
   `ios/release.sh --local` once first if it isn't in the list yet: that registers it), SKU `studystash-ios`,
   primary language English (U.S.).
3. **App Privacy**: the privacy policy URL is `https://study-stash-app.web.app/privacy/`. Data: "Data Not Collected".
   The app sends what it records and asks only to the student's own library, on their own computer, never to us;
   `PrivacyInfo.xcprivacy` says the same. The AI that writes notes and answers questions runs from that library, under
   the student's own account (or on the computer with Ollama), and the privacy policy says so.
4. **TestFlight → Test Information** (needed before external testers, not for internal ones):
   - **Beta App Description**: "Study Stash keeps your lectures. Record a class on your phone, and your computer
     writes study notes from it; read them, study with flashcards and quizzes, ask questions about your lectures,
     see what's due, and write notes by hand in notebooks. This beta has the new look and handwritten notebooks."
   - **Feedback Email**: an address you read.
   - **Privacy Policy URL**: as above. **Marketing URL**: `https://study-stash-app.web.app/`.
   - **Beta App Review Information**: contact name, phone (international format, +1…) and email; **Sign-in
     required: off**; and these notes:

     > Study Stash is the phone half of a free, open-source app: it reads a lecture library that runs on the user's
     > own computer (Mac or Windows), reached over their private Tailscale network. There are no accounts.
     >
     > To review it without a computer, tap **Try it with sample classes** on the first screen. It opens a sample
     > library built into the app, with classes, lectures with notes, a transcript, assignments and a calendar, Ask,
     > Study (flashcards and a quiz), Search and Settings, and recording works in it.
     >
     > Recording: the student taps Record; the microphone is asked for then. While recording, the app shows a red
     > recording bar and a Live Activity, and keeps recording in the background (audio background mode) so a lecture
     > isn't cut off when the screen locks. The recording goes only to the user's own computer.
     >
     > AI: notes and answers are written on the user's own computer by the AI they chose there (Claude, ChatGPT,
     > Gemini or a local model through their own account or Ollama). Nothing is sent to us; we run no servers.
     >
     > Plain http (NSAllowsArbitraryLoads): the library is on the user's own computer, reached at its Tailscale IP
     > address when Tailscale's https isn't set up; Tailscale encrypts that traffic end to end itself.

## Each build

```sh
ios/release.sh
```

It archives, signs and uploads, numbering the build itself. Then in App Store Connect → TestFlight:

- **Internal testing** (no review): add yourself and up to 100 people on the App Store Connect team; the build
  installs from the TestFlight app as soon as it has processed (5–15 minutes).
- **External testing** (up to 10,000 people): make a group, add the build, and turn on the **public link** if you
  want one. The first build of each version goes to Beta App Review (usually about a day); later builds of the same
  version often don't. A build can be tested for 90 days.

## The App Store

Submit a TestFlight build for review with the same notes as above, and:

- **Screenshots**: run the app in the iPhone 17 Pro Max and iPad Pro 13" simulators with the launch argument
  `-demo -quiet` (Xcode → Scheme → Run → Arguments) and take them with ⌘S.
- **Category**: Education. **Age rating**: answer the questionnaire; Ask answers only from the student's own notes.
