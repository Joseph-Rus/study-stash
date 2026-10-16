# The iPhone and iPad app's look

The phone app wears the desktop's Semester look: the same colours, type, icons, rules and words. The desktop wins
where it and the handoff spec (`docs/design/semester-ui-handoff/`) differ. Everything below is in
`StudyStash/Design/` (Theme, Type, Icons, Components, EventRow) and `StudyStash/App/Format.swift`. Use these pieces;
don't make colours, fonts or icons of your own.

## The rules, in one screen

- **Black, grey and white.** Every screen is the page (`.page()`: `Color.surface` to the edges). Grouped rows sit in a
  sunken box (`Panel`, or `.groupedList()` + `.groupedRows()` for a List/Form). Hairlines (`Rule()`, `Color.line`)
  part rows. Three inks: `.ink` for titles and anything you act on, `.inkMuted` for summaries, dates and what the AI
  wrote, `.inkSubtle` for counts, times and placeholders. **No accent colour**: the tint is ink, a filled button is
  ink with the page's colour on it (`.pill(ink: true)`), a link is muted text over a 2-point grey underline
  (`.textLink`).
- **Red means recording or late, nothing else.** `.record` is only the record dot, the level bars and a recording's
  outline; `.late` is only "Missing" and "Was due…". No red weekdays, no orange or green buttons, no red mic on
  something that isn't recording.
- **A class has one highlighter**, shown only as a `Swatch` (lists of classes, pickers), a `Highlight` behind its name
  (a note's folder, an event's class, an assignment in the calendar) and a `FolderTitle`'s underline. Never a dot, a
  side bar, a tint, a status or a filled area. Get it with `app.hue(of: className)`.
- **One typeface**, Atkinson Hyperlegible Next, weight carrying the hierarchy, figures tabular. Use `.textStyle(_:)`
  (or `Font.app(_:)`); never `.font(.headline)`, `.system(...)`, `design: .serif`. Dynamic Type keeps working.
- **The desktop's icons** (Lucide, 1.5 stroke): `Image(icon:)`, `Icon(_:size:)`, `Label(_:icon:)`. No SF Symbols in
  the app's own UI. No icons on note rows, calendar cells, section headings or counts. No sparkles.
- **Sentence case, never uppercase labels.** No pill badges ("In 6 days", "To do"), no metric tiles, no class card
  grids, no "Claude" pill, no glass tinted with a colour.
- **No gradients, anywhere.** No `LinearGradient` (or radial, angular), no `.gradient` on a colour, no fades
  across or down a view, no glowing halos. Flat token colours only. (The only soft edge is a floating thing's
  shadow, `.lifted(...)`.)
- **The real logo, never a stand-in.** Wherever the app shows its logo (setup, pairing, About), it's
  `StudyStashLogo(size:)`: the app icon itself (the navy "S." cut into a paper tile, copper on black in dark), with
  the app icon's corners. Never an SF Symbol, a Lucide icon, or a letter or shape drawn to look like it.
- **No prominent system buttons.** `.borderedProminent` and `.glassProminent` fill with the tint (ink) and write in
  white, which disappears on dark's light ink: use `.pill(ink: true)` (ink filled, the page's colour on it). Likewise
  never `.white` text on `.tint` or `.accentColor`.
- **Words** are the desktop's (`Format`, `Nouns`): "Today", "Yesterday", "Wed 7 Oct", "7 Oct 2025"; "9:30 AM";
  "13 min", "1 h 12 min"; lecture / meeting / recording / notes. Plain, second person, no exclamation marks, no emoji.
- **Motion**: pressing changes colour only; only the recording dot, the level and a caret loop. Respect Reduce Motion.
- **Radius nests**: controls 8 → today's cell 10 → panels, the Ask bar, toasts 12 → the main sheet 14 → pills round.
- It's still iOS: keep the tab bar, push navigation, sheets, swipe actions and the glass the system draws (tab bar,
  toolbars, menus, alerts, the keyboard). Restyle what's inside them. On an iPad (regular width) lean towards the
  desktop's layout: `NoteRow` and `EventRow` already switch to its columns, and page titles take its sizes.

## Colours (`Theme.swift`)

The desktop's `Skin.Palette` by the same names, light and dark, as `ShapeStyle`s:

`.canvas` `.surface` `.surfaceSunken` `.surfaceToday` `.line` `.hover` `.press` `.ink` `.inkMuted` `.inkSubtle`
`.record` `.onRecord` `.late` `.focus` — e.g. `.foregroundStyle(.inkMuted)`, `.background(.surfaceSunken, in: …)`.
UIKit: `Palette.ink` etc.

Highlighters: `Highlighter` (`.yellow .green .pink .blue .orange .violet .teal .lime`), each with `.highlight` (behind
ink text) and `.swatch` (nothing on it). **A class's highlighter is `app.hue(of: name)`** (or
`Highlighter(classIndex: classInfo.color)`), the desktop's mapping (`Skin.ClassHues`): the library's `color` 0, 1, 2…
is yellow, green, orange, pink, blue, teal, violet, lime, then round again. So Calculus II (0) is yellow on both.
Nil means no class (Unsorted, or an event no class matched): a grey wash / grey swatch.

`Radius.control` 8, `.day` 10, `.panel` 12, `.pane` 14; `Space.s1…s14` (4-point steps), `Space.pageCompact` 20,
`Space.pageRegular` 56. Shadows: `.lifted(.float, in: shape)` (the Ask bar, a menu, a toast), `.lifted(.today, in:)`
(today's cell), `.lifted(.floatFocus, in:)` (ringed in ink).

Appearance: `@AppStorage(Appearance.key)` holds `Appearance.system / .light / .dark` ("Match system", "Light",
"Dark"); the root applies it. Settings adds the control.

## Type (`Type.swift`)

`Text("…").textStyle(.lede)` sets font, line height and letter spacing; `Font.app(.lede)` is the font alone;
`Font.atkinson(13, .bold, relativeTo: .footnote)` is any size. `UIFont`: `AppText.date.uiFont()`, `Atkinson.uiFont`.

| `AppText` | Desktop | Use |
| --- | --- | --- |
| `.date` | 800 40/44 (34 on a phone) | A page's title: Home's date ("Friday, October 16"), "Due", a class |
| `.docTitle` | 800 32 (28 on a phone) | A note's title on its page |
| `.h2` | 800 17/24 | Section heading: "Up next", "Notes", "Lectures" |
| `.title` | 700 17/22 | A lecture's or an event's title in a list |
| `.body` | 400 15/22 | Anything else (the app's default) |
| `.lede` | 400 16/24 | The sentence under a title; empty states (ink-muted) |
| `.summary` | 400 14.5/22 | A lecture's summary in a list, two lines (ink-muted) |
| `.nav` | 500 15/20 | A row in a list of places (700 when chosen) |
| `.className` | 400 14/20 | A class in a list of classes |
| `.due` | 700 14/19 | An assignment in the calendar |
| `.meta` | 500 13/18 | Day names, counts, a rail's dates |
| `.micro` | 500 12/16 | Times, footers |
| `.dayNum` | 800 22/26 | A day's number in the week |
| `.when` | 700 14/18 | "Today", "Sat 10 Oct", "1:45 PM" beside a row (ink-muted) |
| `.folder` | 600 13.5/18 | A note's folder (the highlight), "Unsorted" |
| `.length` | 500 14/18 | "52 min" at a row's end (ink-subtle) |
| `.group` | 700 13/18 | "This week", "Classes" over rows (ink-subtle) |
| `.railTitle` | 800 15/24 | A rail's heading: "Due", "On Canvas" |
| `.button` / `.buttonSmall` | 700 15 / 14 | A pill's words / a small pill's, a link's, a picker's |
| `.crumb` | 500 14/18 | "Lecture, Monday 12 October at 9:30 AM, 52 min" |
| `.tab` | 700 15 | Notes \| Transcript |
| `.legend` | 500 12/16 | "What you wrote" / "Added by Claude from the recording" |

`.fontWeight(.bold)` and `.bold()` pick the family's real face. The family has no italic, and `.italic()` leaves it
upright: for the desktop's italic lines (a pending summary, the notes hint) use `.textStyle(.summary, italic: true)`,
which slants the face 12°.
Navigation bar titles (large and inline, and subtitles), the tab bar, segmented controls and the search field are
already Atkinson (`App/SystemLook.swift`). A toolbar button with words is not: iOS 26 draws those itself, so give
the label its style, `Button { … } label: { Text("Done").textStyle(.button) }` (`.nav` for Cancel and the like).
Menus, alerts, confirmation dialogs and the keyboard stay the system's.

## Icons (`Icons.swift`, `Resources/Icons.xcassets`)

```swift
Image(icon: "home")                       // 24 pt, for a tab, toolbar, menu, swipe action, widget
Label("Due", icon: "event_upcoming")      // a menu item, a toolbar button, a swipe action
Button("Delete", icon: "delete", role: .destructive) { … }
Icon("inbox", size: 15)                   // beside text, scales with Dynamic Type, in the foreground style
Image(icon: "stop", filled: true)         // the solid ones: circle, fiber_manual_record, pause, play_arrow, stop
Tab("Home", image: "home", value: .library) { … }
```

Names are the desktop's (`engine/tools/icons/lucide.py` `NAMES`, Material-style, e.g. `arrow_back`, `attach_file`,
`more_horiz`, `expand_more`, `ios_share`, `event_upcoming`), plus the phone's own in `ios/tools/icons.py`
`PHONE_NAMES` (`mic_off`, `document_scanner`, `qr_code_scanner`, `cancel`, `undo`, `page_add`, `page_remove`,
`cloud_upload`, `flashcards`, `work`, `science`, `person`). Every one is listed in `Design/IconNames.swift`, and drawn
in `-show components:4`. The widget extension has them too. Control Center controls and App Shortcuts can only show
SF Symbols (the system draws those): they keep theirs.

**Adding an icon** (any lane may): the desktop's table is read-only from here. Add `"your_name": "lucide-name"` to
`PHONE_NAMES` in `ios/tools/icons.py` (Lucide 0.469.0 names: lucide.dev/icons), then

```sh
mkdir /tmp/lucide && cd /tmp/lucide && npm pack lucide-static@0.469.0 && tar -xzf lucide-static-0.469.0.tgz
python3 -I ios/tools/icons.py /tmp/lucide/package/icons   # writes the image sets and IconNames.swift
```

It refuses a name the desktop already has, and checks every desktop icon still matches `IconPaths.cs`.

### SF Symbol → icon

| SF Symbol | Icon |
| --- | --- |
| `books.vertical` (tab) | `home` (the tab is "Home", as the desktop's sidebar) |
| `books.vertical.fill`, `book.closed.fill` | `book_2` |
| `checklist` (tab) | `event_upcoming` (Due) |
| `sparkles` | `chat` (Ask); `hourglass_top` (notes being written); never a sparkle |
| `gearshape` | `settings` |
| `magnifyingglass` | `search` |
| `plus` | `add` |
| `mic`, `mic.fill` | `mic` |
| `mic.slash` | `mic_off` |
| `waveform` | `graphic_eq` (or `LevelBars` for a live level) |
| `stop.fill` | `stop` filled |
| `pause.fill`, `pause.circle.fill` | `pause` filled |
| `play.fill` | `play_arrow` filled |
| `record.circle` | `RecordDot` (or `fiber_manual_record` filled) |
| `star.fill` (mark a moment) | `bookmark` |
| `star` (points) | `grade` |
| `pencil.and.scribble` | `edit_note` |
| `pencil` | `edit` |
| `doc.viewfinder` | `document_scanner` |
| `photo`, `photo.on.rectangle` | `image` |
| `folder` | `folder` |
| `doc` | `draft` |
| `doc.text`, `doc.plaintext` | `description` |
| `doc.richtext` | `picture_as_pdf` |
| `rectangle.on.rectangle` | `slideshow` |
| `rectangle.on.rectangle.angled` | `flashcards` |
| `rectangle.on.rectangle.slash`, `exclamationmark.triangle(.fill)` | `warning` |
| `paperclip` | `attach_file` |
| `square.and.arrow.up` | `ios_share` |
| `safari` | `open_in_new` |
| `trash` | `delete` |
| `ellipsis`, `ellipsis.circle` | `more_horiz` |
| `checkmark` | `check` |
| `checkmark.circle(.fill)`, `checkmark.seal(.fill)` | `check_circle` |
| `xmark` | `close` |
| `xmark.circle.fill` | `cancel` |
| `chevron.left` / `.right` / `.down` | `chevron_left` / `chevron_right` / `expand_more` |
| `chevron.up.chevron.down` | `unfold_more` |
| `arrow.up` | `arrow_upward` |
| `arrow.up.right` | `arrow_outward` |
| `arrow.uturn.left` | `undo` |
| `arrow.clockwise` | `refresh` |
| `arrow.up.circle`, `tray.and.arrow.up(.fill)` | `upload` |
| `tray` | `inbox` (Unsorted) |
| `wand.and.stars` | `drive_file_move` (file events in a class); `inbox` ("Let Study Stash sort it") |
| `icloud.slash` | `cloud_off` |
| `wifi.slash` | `wifi_off` |
| `icloud.and.arrow.up` | `cloud_upload` |
| `checkmark.icloud` | `cloud` |
| `qrcode.viewfinder` | `qr_code_scanner` |
| `plus.rectangle.portrait` / `minus.rectangle.portrait` | `page_add` / `page_remove` |
| `rectangle.righthalf.inset.filled` | `dock_to_right` |
| `text.quote` | `notes` |
| `bubble.left.and.bubble.right` | `forum` |
| `calendar` | `event` |
| `circle`, `circle.dashed` | `radio_button_unchecked` |
| `graduationcap.fill` | `school` |
| `briefcase.fill` | `work` |
| `flask.fill` | `science` |
| `paintpalette.fill` | `palette` |
| `person.fill` | `person` |

## Components (`Components.swift`, `EventRow.swift`)

```swift
StudyStashLogo(size: 64)                              // the real logo (image set "Logo", light and dark), rounded
Swatch(app.hue(of: cls))                              // 14 × 10 mark; Swatch(hue, small: true) 9 × 7
Highlight("Calculus II", hue: app.hue(of: cls))       // .folder size; style: .title / .due; struck:, outlined:
FolderTitle("Calculus II", hue: app.hue(of: name))    // a class page's title, underlined in its highlighter
NavigationLink(value: Route.lecture(l.id)) { NoteRow(lecture: l) }.buttonStyle(.plain)
                                                      // when | title, folder, summary | length; first: true for no
                                                      // rule above; showFolder: false on a class page; onFolder: { }
EventRow(event: e)                                    // Up next: the whole row records it
SectionHeading(title: "Up next")                      // trailing: "See all", action: { }
GroupLabel("This week")
Rule()
Panel(padding: 0) { … }                               // a grouped box (replaces Card)
List { Section { … }.groupedRows() }.groupedList()    // a List/Form in the look
Button { } label: { Label("Attach", icon: "attach_file") }.buttonStyle(.pill)   // .pill(small: true), .pill(ink: true)
Button("See these on the calendar") { }.buttonStyle(.textLink)
Button { } label: { Label("Open in Canvas", icon: "open_in_new") }.buttonStyle(.quiet)
Menu { … } label: { PickerLabel("All notes") }.buttonStyle(.picker)
Button { } label: { Label("Search", icon: "search") }.buttonStyle(.icon)       // .icon(small: true)
Button { } label: { row }.buttonStyle(.row)           // a whole row, washed while pressed
RecordButton(state: .idle) { start() }                // .recording / .paused, words:, elapsed:, levels:, stop:
RecordDot(state: .recording, mini: true)
LevelBars(levels: recorder.levels)                    // three red bars
AskBar(placeholder: "Ask anything about your notes", text: $q, scope: "All notes") { send() }
AskBarButton(placeholder: "Ask about this lecture", scope: "This lecture") { asking = true }
EmptyText("No lectures yet. Record one here, or attach a recording.")
EmptyState(title: "Can't reach your library", detail: "…", actionTitle: "Try again") { }   // replaces ContentUnavailableView
Toast("Moved to Calculus II.", actionTitle: "Undo") { }      // or .toast($message) on a view
OfflineNote()
TabStrip(selection: $pane, tabs: [(.notes, "Notes"), (.transcript, "Transcript")])
Segmented(selection: $mode, options: [(.month, "Month"), (.week, "Week")])
Toggle("Only my notes", isOn: $only).toggleStyle(.ink)
TopicChips(topics: l.topics)                          // plain muted words, parted by dots
Loaded(resource: r) { value in … }                    // loading / failed / loaded, in the look
```

Gone with the look before: `ColourTheme` (the colour themes; the tint is ink), `ClassColor` (dots; use `Highlighter`),
`ClassDot` (use `Swatch`), `LectureCard` (use `NoteRow`), `Card` (use `Panel`), `Color.paper` / `.card` (use
`.surface` / `.surfaceSunken`), `Font.display` / `.titleSerif` / `.headlineSerif` (use `AppText`). Call sites were
renamed, not restyled. `app.color(of:)` is deprecated and now returns ink: its warnings mark the places a class colour
was used as a tint, which the page lanes remove (use `app.hue(of:)` with a Swatch or Highlight).

## Words (`App/Format.swift`)

`Format.day(d)` "Today" / "Yesterday" / "Tomorrow" / "Wed 7 Oct" / "7 Oct 2025"; `Format.date(d)` "Mon 12 Oct"
(a class page's rows); `Format.time(d)` "9:30 AM"; `Format.longDate()` "Friday, October 16" (Home's title);
`Format.duration(s)` "48 min", "1 h 12 min", "2 h 00 min"; `Format.noteWhen(date, seconds)` "Monday 12 October at
9:30 AM, 52 min"; `Format.lectureGroup(date)` "This week" / "Last week" / "September" (weeks start Sunday);
`Format.dueWhen(due)` "Tomorrow, 9:00 AM"; `Format.railDue(due, late:)` "Sun 18 Oct, in 6 days", "Was due Mon 5 Oct";
`Format.inMinutes(t)` "in 11 minutes"; `PlainMath.inline(summary)` (a summary's LaTeX as plain characters).
Nouns: `app.noun(of: cls)` "lecture" / "meeting" / "recording" (a class in Classes, a folder in Clubs or Work, none);
`Nouns.section(noun)` "Lectures"; `Nouns.untitled(folder:date:)` "Recording, Sat 10 Oct at 4:12 PM". Mixed lists
say "notes" ("Ask anything about your notes"). The library now sends a class's `group` (`ClassInfo.group`).

## Which desktop page each phone page is

| Phone | Desktop view | Desktop pictures (`iphone-look-refs/desktop/`, `docs/design/`) |
| --- | --- | --- |
| Home tab (`LibraryTab`) | `Views/Overview.axaml` (Home), `NoteRowView.axaml` | `mac-40-home-*`, `mac-42-home-narrow-*`; handoff `home-*` |
| A class (`ClassView`) | `Overview.axaml` (a folder), its rail | `mac-41-folder-*`, `mac-42-folder-narrow-*`; `folder-class-*` |
| A lecture (`LectureView`, `NotesView`) | `Views/NotePage.axaml` | `mac-43-note-*`; `note-*` |
| Recording (`RecordView`) | `NotePage.axaml` recording, `MacRecorder.axaml` | `mac-45-recording-*`, `mac-02-recorder-*`; `recording-*` |
| Due (`DueViews`) | `Views/DueCalendar.axaml`, `WeekPlanner.axaml` | `mac-44-due-*`, `mac-19-due-dark`; `due-*` |
| An assignment | Canvas's assignment sheet | `mac-09-canvas-due-app-*`, `mac-10-canvas-class-*` |
| Ask (`AskViews`) | `MacAiAskBar`, `MacAiAnswer`, `MacAiAskChat` | `mac-16-ai-*`, `mac-04-full-app-answer-*` |
| Search | `MacQuick.axaml` (the quick panel) | `mac-04-full-app-*` |
| Settings, Uses | `SettingsView.axaml`, `MacPhones.axaml` | `mac-settings-*`, `mac-13*`, `mac-14*` |
| Pairing, first screens | `MacSetup.axaml`, `MacGuidedSetup.axaml` | `mac-05-setup*`, `docs/qa/2026-10-15/setup-new-look/after-*` |
| Toasts | the desktop's notifications | `mac-12-toast-*`, `mac-12-notify-*` |
| Study, notebooks, add files, widgets | none: build from the pieces above | the component pictures (`-show components:1…4`) |

## Opening any screen (debug builds)

`DebugLaunch` in `App/StudyStashApp.swift`; always with `-demo` (the demo library in the app; never pair with a real
one) and `-quiet` (no notification prompt):

- `-tab home|due|ask|settings|search`; `-search <words>` (Search with them typed)
- `-open lecture:<id>` (`demo-calc-ibp`, `demo-psych-memory`, `demo-chem-sn`, `demo-unsorted-study-group`),
  `-open class:<name>` (`Calculus II`, `Intro to Psychology`, `Organic Chemistry`), `-open assignment:<class>:<id>`
  (`Calculus II:1`), `-open search:<words>`; `-pane notes|transcript|files` for a lecture
- `-show record` (records made-up lines; `-stop-after 3` for the sent screen), `ask`, `ask:lecture:<id>`,
  `ask:class:<name>`, `add-files`, `import-audio`, `goodnotes`, `handwriting` (a new notebook each time), `notebook`,
  `study:<id>`, `quiz:<id>`, `uses`, `widgets` (`WidgetGallery`, in `Shared/WidgetGallery.swift`), `components:1…4`
  (every shared piece)
- `-ask "<question>"` with `-tab ask`; `-unpaired` (setup, no `-demo`), with `-pair-code` its second step
- Your own: read `DebugLaunch.flag("-x")` / `DebugLaunch.value("-x")` in your own file.

The demo library: three classes (Calculus II yellow, Intro to Psychology green, Organic Chemistry orange), four notes
(one unsorted, untitled), three assignments, three events.

## Pictures

```sh
xcrun simctl create "iphone-look-<lane>" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-2
ios/tools/shots.sh -u <udid> -o <folder> home class 'home-scrolled=-tab home -scrolled'
ios/tools/shots.sh -l        # the screens it knows
```

It builds (`-jobs 2`, `ios/build/dd`) unless you give `-a <StudyStash.app>`, installs, and takes each screen light and
dark (`<name>-light.png`, `<name>-dark.png`), then shuts the simulator down (`-k` keeps it up). The same on an iPad
simulator (`…SimDeviceType.iPad-Air-11-inch-M3`). Delete your simulator when you're done. Before and after pictures of
every screen: `iphone-look-refs/iphone-before/`, `iphone-look-refs/iphone-foundation/`.
