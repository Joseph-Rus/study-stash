# Releasing the iPhone and iPad app

## Once

The app's name in App Store Connect (App Information → Name) is set by hand there, not by this repo; it must be "Syft Notes" (the home-screen name comes from `project.yml`).

1. **Xcode → Settings → Accounts**: sign in with the Apple ID on the developer team in `project.yml`
   (`DEVELOPMENT_TEAM`, joey russell G67978NLXW), as Account Holder or Admin, so Xcode can make the distribution
   certificate and profiles itself. Done on Joey's Mac by 2026-10-23: `app.studystash.ios` and
   `app.studystash.ios.widgets` are registered on that team, with App Store profiles.
2. **App Store Connect → Apps → +, New App** (Apple's API can't make this; only the website or Xcode's Distribute
   window can): iOS, name *Syft Notes* (it was made as Nerd Notes, then Pylorum; rename it under App Information → Name), primary language English (U.S.), bundle ID `app.studystash.ios`, SKU
   `nerdnotes-ios` (a SKU can never change, and nobody sees it), Full Access. Until it exists an upload stops at "Error Downloading App Information" (the
   distribution log says `missingApp`).
3. **TestFlight → Internal Testing → +**: a group (say *Team*) with **automatic distribution** on, and yourself in it.
   Every build uploaded after that shows in the TestFlight app on your phone by itself.
4. **App Privacy**: the privacy policy URL is `https://study-stash-app.web.app/privacy/`. Data: "Data Not Collected".
   The app sends what it records and asks only to the student's own library, on their own computer, never to us;
   `PrivacyInfo.xcprivacy` says the same. The AI that writes notes and answers questions runs from that library, under
   the student's own account (or on the computer with Ollama), and the privacy policy says so.
5. **TestFlight → Test Information** (needed before external testers, not for internal ones):
   - **Beta App Description**: "Syft Notes keeps your lectures. Record a class on your phone, and your computer
     writes study notes from it; read them, study with flashcards and quizzes, ask questions about your lectures,
     see what's due, and write notes by hand in notebooks. This beta has the new look and handwritten notebooks."
   - **Feedback Email**: an address you read.
   - **Privacy Policy URL**: as above. **Marketing URL**: `https://study-stash-app.web.app/`.
   - **Beta App Review Information**: contact name, phone (international format, +1…) and email; **Sign-in
     required: off**; and these notes:

     > Syft Notes is the phone half of a free, open-source app: it reads a lecture library that runs on the user's
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

## External testing: what to paste

App Store Connect → the app → **TestFlight** → **Test Information** (once), then a group under **External Testing**
with the build, then **Submit for Review**.

- **Beta App Description:** Syft Notes records your lectures and turns them into notes on your computer. This app
  is its companion: read your notes and lectures, see what's due, ask questions about your classes, record a lecture
  on the phone (it's written down on the phone), and take whiteboard photos that go into your notes. It links to
  Syft Notes on your computer through your own Google Drive.
- **What to Test** (per build): record a lecture on the phone (it keeps going while you take a whiteboard photo);
  Ask a question, including "what's due this week?"; take whiteboard photos while your computer records; open a
  lecture's notes and its photo strip. Tell us anything that's confusing, slow or wrong.
- **Feedback email:** the one testers should write to.
- **Sign-in required:** No.
- **Review notes:**
  > No account is needed to review the app. On the first screen tap **Other ways → Try it with sample classes**: the
  > whole app runs on sample classes stored on the phone (Home, a lecture's notes, Due, Ask, Search, recording).
  > For real use the app pairs with Syft Notes on the student's own computer. "Continue with Google" is not an
  > account with us: it only lets the app reach a private Syft Notes folder in the student's own Google Drive
  > (Google's application data folder scope), which their computer also uses. So it isn't a sign-in service under
  > guideline 4.8. The microphone is used only while recording; speech is written down on the device; the camera is
  > used only to take whiteboard photos.

**Before the first external build:** Google's sign-in must be out of Testing (Google Auth Platform → Audience →
**Publish app**). In Testing only listed test users can press Allow; everyone else sees "Access blocked".

## The App Store

Submit a TestFlight build for review with the same notes as above, and:

- **Screenshots**: run the app in the iPhone 17 Pro Max and iPad Pro 13" simulators with the launch argument
  `-demo -quiet` (Xcode → Scheme → Run → Arguments) and take them with ⌘S.
- **Category**: Education. **Age rating**: answer the questionnaire; Ask answers only from the student's own notes.
