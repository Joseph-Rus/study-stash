# How each AI shows it's thinking

Ask shows which AI is answering by redrawing how that product itself shows thinking. These are not its logo scaled
and moved. Everything is drawn in `StudyStash/Screens/Ask/ThinkingMotion.swift` from shapes, paths and text, in a
`TimelineView` with a `Canvas`. With Reduce Motion each shows one still frame and the words don't shimmer. VoiceOver
reads "Claude is thinking", "ChatGPT is thinking" and so on.

Numbers marked *source* come from code or a write-up listed below. Numbers marked *by eye* were matched to the products
as they look, because their makers don't publish them.

## Claude

**Before any words: Claude Code's spinner.** Six glyphs play forward and then back, so the loop is
`· ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢` (*source*: the glyph set from Claude Code's `cli.js` and the forward-then-back order). Each
frame lasts 120 ms (*source*: the pi-claude-shimmer recreation). The colour is Claude's terracotta `#D97757`. Claude
Code's own terminal colour, `rgb(215,119,87)`, is one step from it.

The glyphs are drawn as paths so that iOS can't swap in its emoji ✳️:

| Glyph | Name | Drawn as |
|---|---|---|
| · | interpunct | a dot |
| ✢ | four teardrop-spoked asterisk | 4 teardrops, points in |
| ✳ | eight-spoked asterisk | 8 round-capped lines |
| ✶ | six-pointed black star | a filled 6-point star |
| ✻ | teardrop-spoked asterisk | 8 teardrops |
| ✽ | heavy teardrop-spoked asterisk | 8 fatter teardrops, turned 22.5° |

The status words get Claude Code's shimmer: a lighter band moves through them one letter at a time. The band is 3
letters wide on each side and fades to 45% at its middle. It steps every 100 ms (*source*: the pi-claude-shimmer
recreation uses a 4-letter band with a linear falloff, stepping every 50 to 200 ms). Each letter gets one flat shade,
so there is no gradient.

**While words arrive: the Claude apps' spark.** The spark has 12 rays, slightly uneven in angle and length like the
mark. A sweep goes round clockwise once every 1.2 s (*by eye*). Each ray snaps to a third of its length as the sweep
passes, then grows back over the next three quarters of the turn with an ease-out. The spark is redrawn 12 times a
second, with a slight wobble in each frame, so it reads as hand-drawn (*source*: greatgitsby's recreation, "redrawn
twelve times a second, hand-drawn style; a sweep runs clockwise round it, each ray snapping short as it passes and
growing back behind it").

## ChatGPT

**The dot.** A filled circle in ink: black on light, white on dark, as ChatGPT's own dot is. It swells from 80% to full
size and settles back every 1.25 s, eased in and out (*by eye*). It sits where the answer will start (*source*: the
black dot that shows while ChatGPT is working, layer3labs).

**The words** get the smooth shimmer of a reasoning model's "Thinking". A lighter band, 5 letters on each side and
down to 35%, sweeps left to right in about 2 s (*by eye*).

## Gemini

**The sparkle.** Gemini's four-pointed star, with its sides curved in towards the centre. Its outline follows the
mark's path, simplified to four quadratic curves. It is filled with Gemini's own colours at 135°:
`#217BFE → #078EFB → #AC87EB → #217BFE`, at four times the star's size. The colours slide through it once every 3 s
(*source*: CSS-Tricks' recreation of Gemini's animation uses this gradient at 400% and translates it). The star turns
half a turn every 2 s, eased in and out like Gemini's 180° ease-in-out turn (*source*: CSS-Tricks), and shrinks to 93%
mid-turn. Gemini's gradient is the one allowed exception to "no gradients", as it is for its mark.

**The words** get a quicker shimmer: a band 4 letters wide that crosses them in 1.5 s (*by eye*).

## Ollama

**Its command line's braille spinner.** The frames are `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`, one every 100 ms, with no colour of their
own (*source*: `progress/spinner.go` in ollama/ollama). The dots are drawn on the six-dot braille grid in ink, lit dots
only, because terminals show the glyph's lit dots. The words stay plain, as Ollama's do.

## Not known yet

When no AI is known yet, three dots in the subtle ink fade in a wave.

## Loading (`StudyLoader`)

This isn't any product's animation. It's the app's own, organic one. Three drops drift round each other, flow
together into one and part again, like liquid. The drops are blurred, then cut at half (`alphaThreshold`), so where
they meet they join into one flat shape in the given colour, with no gradient. The drops part and join every 2.4 s, the
whole thing turns once every 1.9 s, and each drop wanders and swells a little on its own wave. The still frame shows
the three drops apart. It was chosen over two other candidates: a loop whose outline breathes and morphs, and three
strands swaying like seaweed. Both read less clearly as "loading" at 14 pt.

## Sources

- Claude Code's glyphs, read from its `cli.js`: Alex Beals, "Claude Code's thinking animation",
  https://blog.alexbeals.com/posts/claude-codes-thinking-animation
- The forward-then-back order, 120 ms frames, the shimmer band and the colours `#D77757` and `#F59575`:
  pi-claude-shimmer, https://github.com/ouzhenkun/pi-claude-shimmer (`index.ts`)
- The Claude apps' spark, its 12 fps sweep: "Animate the Claude spark like it does in the Claude apps",
  https://github.com/greatgitsby/website/pull/4
- Gemini's gradient, turn and easing: CSS-Tricks, "Recreating Gmail's Google Gemini Animation",
  https://css-tricks.com/recreating-gmails-google-gemini-animation/
- Gemini's loader shapes (morph, rotate, scale): 60fps.design, https://60fps.design/shots/google-gemini-loader-animation
- Ollama's spinner: https://github.com/ollama/ollama/blob/main/progress/spinner.go
- ChatGPT's dot: https://www.layer3labs.io/guides/chatgpt-dot-meaning
