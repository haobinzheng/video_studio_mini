# FluxCut Design Notes

Use this file to capture design framing and validated conclusions as the product evolves.

## Slideshow

- mode name is now `Slideshow` instead of `Real-Life` in `VideoExporter.swift`
- all-photo `Slideshow` now uses:
  - `3` seconds per photo as its base pacing
- `Slideshow` duration is still:
  - `max(media duration, narration duration)`
- if narration is longer:
  - media now loops to fill it
- if media is longer:
  - narration simply ends when it ends
- captions remain off
- the smooth composition-first render path stays in place

Design note:

- `Slideshow` will get the same export controls UI as `Video`, and the exporter will honor high settings when media is the clock
- if narration is longer than media, keep the same UI selection but clamp the actual `4K 60 High` path down to a safer profile under the hood so FluxCut does not promise a combination that is too risky for the looping case

## Big-stage video preview (Media tab & Edit Assign)

**Full code design spec (copy-friendly):** [`docs/BIG_PREVIEW_VIDEO_AUTOPLAY_SPEC.md`](BIG_PREVIEW_VIDEO_AUTOPLAY_SPEC.md)

**Product behavior**

- Large **muted** looping preview for pool videos (`ProjectVideoStageView` → `LoopingVideoPreview` in `ContentView.swift`).
- **Autoplay** when the carousel slide is active and playback can start; user does **not** need to tap Play.
- **Optional Play** while still loading = early start only; when the clip is **ready**, the spinner + Play control **hide** and playback should already be requested (extra `play()` calls are harmless).

**Implementation gist (why it feels “instant”)**

- **`AVPlayerLooper`** plays **replica** items, not only the template `AVPlayerItem`. Relying on **template `AVPlayerItem.status` alone** can miss readiness; the store also observes **`AVPlayerLooper.status == .ready`** and treats **either** looper-ready **or** item `readyToPlay` as “show video.”
- When the slide becomes active, the store calls **`player.play()`** immediately (as in Apple’s looper sample), not only after a SwiftUI `onChange` on a published flag—so AVFoundation can start as soon as the looper/item allows.
- Slide visibility is driven by **`setSlideActiveForPreview`** from `onAppear` / `onChange(isActive)` / `onDisappear`, not by fragile `onChange` on `isReadyForPlayback` alone.

For file/symbol index, failure handling, and a manual test checklist, use the linked spec.

## Story

Story mode design record:

- `Story` is narration-driven
- the narration is the clock
- if narration exists, final duration follows narration
- if narration does not exist, FluxCut falls back to the media-driven minimum visual duration

Media behavior:

- selected media stays in user order
- videos use their natural clip durations
- photos are assigned story-style durations from the remaining narration time
- if narration is longer than one media pass, the sequence can rotate to keep filling the narration timeline

Caption behavior:

- optional **display-only** tail trim removes **soft** terminators (ASCII/CJK `,` `.` `;` `:` `…` and fullwidth `．` etc.) from the **end of each caption line** using single-scalar matching so it stays reliable; it does **not** strip closing `)` `]` `}` `"` `?` `/` or similar, so parentheticals and quotes stay intact
- **Script narration preview** (`NarrationPreviewBuilder`): caps how many sequential `AVSpeechSynthesizer.write` passes run by **merging** adjacent segments when there would otherwise be too many (long scripts used to feel “stuck”); each pass has a **timeout** so a stuck synthesizer cannot hang the UI forever; **final export** still uses the full segmented pipeline
- captions are optional for final export
- if `Include Captions` is on:
  - FluxCut uses the safer classic story renderer
  - captions are burned into the final video
- if `Include Captions` is off:
  - FluxCut still uses the same story timing
  - but the render profile switches to a smoother video-style profile

Caption-off Story render profile:

- source-preserving render sizing
- preview: `12 fps`
- final standard: `24 fps`
- final high: `30 fps`
- no classic long-form story downshift in this path

Audio behavior:

- narration is primary
- background music is optional
- original video sound is mixed using `Final Mix`

Product framing:

- `Story` = narration-led storytelling
- captions on = safer subtitle-first story render
- captions off = same story pacing, smoother video-style visual finish

## Edit Story (Pro workspace)

Implemented in the **Edit Story** tab (optional; Settings → **Show Edit Story tab** toggles visibility, default on for development):

### Segments, media vs music (terminology)

- **Media block**: one contiguous range of script **paragraphs** plus ordered pool clips (`AppViewModel.StoryEditBlock`: `firstParagraphIndex`…`lastParagraphIndex`, `mediaItemIDs`). Visual timeline only.
- **Music segment**: an independent contiguous paragraph range with its own soundtrack choice (`AppViewModel.StoryMusicBedSegment`). It does **not** have to align with media blocks—e.g. media block 1 can be paragraphs 1–3 while music segment 1 spans 1–6.
- **Edit tab structure**: segmented **Media** | **Music** (when **Edit Media and Music** is on). **Media** is script paragraphs labeled **Block** (track order/imports stay on the main **Music** tab). **Music** shows the same script with music assignment captions. Music **Assign** opens the soundtrack sheet for any valid contiguous paragraph selection (after the same gate as media: **Edit Media and Music** on and media assigned somewhere).

### Per–music-segment soundtrack rules (product)

- **One bed per music segment**: at most **one** assigned soundtrack (library track or Music-tab combined mix) per contiguous music span; overlapping spans are merged/replaced on assign.
- **Always start at 0:00**: when that span’s narration plays, its bed **starts at the beginning** of the chosen source for that span.
- **Shorter narration than track**: play from 0:00 and **trim** when the span ends.
- **Same track on another span**: allowed; each span **starts that file at 0:00**.
- **Shorter track than narration**: **loop** to cover the span duration.

### Current implementation notes

- **Paragraphs** match `StoryScriptPartition.nonEmptyParagraphs`: split on blank lines (`\n\n+`); whitespace-only chunks dropped.
- **Media blocks** are `AppViewModel.StoryEditBlock` (paragraph range + `mediaItemIDs`). **Music** is `AppViewModel.storyMusicBedSegments` (`StoryMusicBedSegment`: paragraph range + optional library track id, or nil for Music-tab mix). Not embedded in the script string.
- **Export** when **Edit Media and Music** is on, Story mode is selected, and validation passes:
  - Narration uses **whole-script-style** segmentation **per block** (`StoryScriptPartition.narrationSegmentsWholeScriptStyle`), then measured utterance lengths; timeline length and block composition use **measured TTS only** (no `max(measured, estimated)` inflation) so slideshow frames stay aligned with audio.
  - `VideoExporter` builds a global visual timeline by concatenating per-block segments: **photos only** → even split across the block; **mixed or all video** → cycle user media order with **up to 10s** per photo visit and natural clip length per video visit, filling the block’s narration duration. If block composition cannot run while block mode is on, export fails fast instead of falling back to caption-off “split pool across whole story” pacing.
  - If **Edit Media and Music** is on and validation passes but `makeStoryBlockExportDescriptor()` fails, **AppViewModel** aborts before export with a clear message (avoids legacy pool-wide story pacing). **Preview** with Edit Story blocks uses up to **180s** of measured narration (not the default **20s** preview cap) so multi-block photo timing can be checked.
  - **Background music (Edit Story with block-based export)**: `AppViewModel` passes `makeStoryMusicBedSpansForExport()` as `storyMusicBedSpans` (global paragraph indices + optional URL). `VideoExporter.buildStorySegmentMusicSlots` maps paragraph-level narration timing to beds: assigned URL or Music-tab **combined** `backgroundMusicURL` per span; gaps use the combined mix. Each bed **starts at 0:00**, **trims**/**loops** as above. Non-Edit-Story Story exports still use a single looped global bed.
- **Validation**: every non-empty paragraph must lie in exactly one block; each block needs ≥1 pool medium; pool IDs must resolve. Failures set `isStoryBlockExportBlocking` and disable Preview/Create Video.
- **Script edits**: `reconcileStoryEditBlocksWithScript()` clamps media blocks; `reconcileStoryMusicSegmentsWithScript()` clamps `storyMusicBedSegments` to valid paragraph indices (user may need to re-partition).

### Segment media assignment sheet (full-screen)

Opened from **Edit** when the user selects a contiguous paragraph range and taps **Assign** (media / visual assignment for that segment).

- **Narration meta** (orange capsule): uses `AppViewModel.blockNarrationEstimateMetaLine(paragraphRange:)` so **estimated length and character count** refer to **that block’s** joined paragraphs only, not the full script (same heuristic as global narration estimate, scoped to the range).
- **Segment script**: A read-only scrollable card sits **between** the horizontal **pool** thumbnail strip and **Studio Tip**, showing the paragraph text for the selected range (`storyScriptParagraphs` joined with `\n\n`) so media choices stay aligned with what will be spoken in that segment.
- **Large preview controls**: **+** adds the **current** pool clip to the block draft; **−** removes it from the draft (no ellipsis menu).
- **Assigned to this segment (order)**: Thumbnails reflect draft `mediaItemIDs`; **video** clips show a **video** badge. **Tap** jumps the big preview to that clip; **double-tap** removes it from the draft. **Reorder** uses the same **drag-and-drop** as the **Media** tab (`onDrag` + `onDrop` with `UTType.text` / UUID string). Only the **draft** is mutated until **Done**; global pool order is unchanged.
- **Muted looping preview**: Autoplay is driven in **`LoopingVideoPlayerStore`** using **`AVPlayerLooper.status`** and template **`AVPlayerItem.status`**, plus **`player.play()`** when the slide becomes active (see **Big-stage video preview** above and `docs/BIG_PREVIEW_VIDEO_AUTOPLAY_SPEC.md`). Optional **Play** while buffering remains an early-start affordance.
- **Studio Tip** below the block script summarizes swipe, pool thumbnail tap / double-tap, **+** / **−** on the preview, and assigned-strip gestures.

## Preview Video Disable-State Design

Current problem:

- `Preview Video` has been disabled based on `hasPendingPreviewChanges`
- that means FluxCut must perfectly detect every input change that affects preview
- in practice, too many inputs can change:
  - script
  - voice
  - media selection
  - media order
  - music import/remove
  - music volume
  - narration volume
  - original video sound volume
  - aspect ratio
  - mode

Why this is fragile:

- missing any one invalidation causes a stale-state bug
- example: voice changed, but preview button stayed disabled incorrectly
- the disable logic becomes hard to trust and hard to maintain

New framing:

- `Preview Video` should be disabled only when preview cannot run right now
- not when FluxCut thinks nothing changed

So `Preview Video` should be disabled only if:

- media is still loading
- there is no renderable media for the current mode
- a preview render is already running
- a final render is already running
- narration preview preparation is currently running

What should no longer disable it:

- `preview is already up to date`
- dirty-state bookkeeping like `hasPendingPreviewChanges`

Recommended role of dirty state:

- keep dirty state only for UI messaging
- example:
  - `Preview Sample` when changes exist
  - `Up to date` when preview matches current inputs

Product rule:

- tapping `Preview Video` should always rebuild preview from current inputs whenever rendering is available
- enablement should answer only:
  - `Can preview run now?`
- not:
  - `Did FluxCut detect enough changes to justify it?`

Design benefit:

- simpler behavior
- fewer stale-state bugs
- more trustworthy preview button
- easier future maintenance

## Narration Voice Design

Goal:

- make voice selection language-first and easy to use, while only allowing:
  - `Enhanced`
  - `Premium`
  voices

Voice eligibility rule:

- only voices with quality:
  - `Enhanced`
  - `Premium`
  should be shown for user selection
- do not show:
  - `Default`
  - novelty voices

So the selectable voice library is:

- Apple device voices
- filtered to supported high-quality voices only

New product model:

- voice selection becomes a 2-step flow:
  - choose `Language`
  - choose `Voice`

Main UI:

- rename `Selected Voice` to:
  - `Narration Voice`
- inside that area, show 2 controls:
  - `Language`
  - `Voice`

Language:

- first-class control
- user explicitly chooses language
- only languages that currently have at least one `Enhanced` or `Premium` voice should appear

Voice:

- show only eligible voices inside the selected language
- each row is easy to scan

Voice row content:

- first line:
  - voice name
  - quality label: `Enhanced` or `Premium`
- optional second line:
  - region / variant if helpful

Example:

- `Language: Mandarin`
- `Tingting • Premium`
- `Meijia • Enhanced`

Behavior:

- when language changes:
  - voice list updates immediately
  - if current voice is outside that language, FluxCut auto-selects the best available eligible voice in the new language
- when voice changes:
  - that becomes the active narration voice
- FluxCut remembers both selected language and selected voice

Language availability rule:

- a language should appear only if the device currently has at least one:
  - `Enhanced`
  - `Premium`
  voice in that language

So if Japanese has only default voices on the device:

- Japanese does not appear yet

Why this is good:

- much simpler list
- higher quality by default
- users do not waste time scanning low-quality entries
- language choice becomes obvious and trustworthy

Product framing:

- `Narration Voice` is a curated high-quality voice selector:
  - language-first
  - only enhanced/premium
  - easy to browse
  - device-aware

That also means the current implementation idea stays partly true:

- keep the `high-quality only` rule
- but redesign the UI so users can actually navigate it by language

## Music

Goal:

- allow users to select multiple audio files, reorder them, combine them into one internal soundtrack, preview the merged result, and use it in video export

Product intent:

- FluxCut should support a simple soundtrack-building workflow inside the `Music` tab:
  - choose multiple songs
  - arrange their order
  - merge them into one continuous internal music file
  - preview and scrub that merged soundtrack
  - use it like the current single music import

V1 scope:

- import multiple audio files
- preserve selected order initially
- allow manual reorder inside `Music`
- merge tracks end-to-end into one internal soundtrack
- treat the merged soundtrack as the active music file
- allow playback and scrubbing of the merged soundtrack

User flow:

- user opens `Music`
- user imports multiple audio files
- FluxCut shows them in a soundtrack queue
- user can reorder tracks, similar to `Media`
- FluxCut rebuilds the combined soundtrack after order changes
- user can:
  - play
  - pause
  - stop
  - scrub through the merged soundtrack
- final preview/export uses that merged soundtrack as music

UI model:

- `Music` tab should gain a queue section:
  - list of selected audio tracks
  - each row shows:
    - track name
    - duration
  - rows can be reordered
- below or near playback controls:
  - merged soundtrack playback area
  - seek bar / scrub slider
  - current time / total time
  - play / pause / stop

Internal model:

- FluxCut should maintain:
  - selected soundtrack items in order
  - one merged internal audio file
  - one active merged soundtrack URL for playback/export

So under the hood:

- many source files
- one merged working file

Merge rule:

- tracks are concatenated sequentially:
  - end-to-end
  - no overlap
  - no crossfade in V1
  - no per-track volume in V1

Playback rule:

- playback uses the merged internal soundtrack:
  - same active music concept as today
  - one audio file
  - seek/scrub supported

Export rule:

- video preview/final export should use:
  - the merged soundtrack file
  - exactly like current single imported music

So `Story` / `Slideshow` / `Video` render logic should not need a major redesign:

- they still receive one music URL

Rebuild behavior:

- FluxCut should rebuild the merged soundtrack when:
  - track order changes
  - tracks are added
  - tracks are removed
- during rebuild:
  - playback should stop
  - show a short progress/status message
  - re-enable playback when merged file is ready

Out of scope for V1:

- crossfades
- fades in/out
- per-track trimming
- per-track volume
- multi-track overlays
- waveform editing
- beat matching

Storage:

- FluxCut should store:
  - source imported audio files as today
  - one merged working soundtrack file
- old merged files should be replaced/cleaned up when rebuilt

Complexity:

- feature size: medium to medium-high
- technical risk: moderate
- product value: high

Main risks:

- long merge times for large audio sets
- format compatibility across different source files
- rebuild timing after reorder
- storage growth if merged files are not cleaned up

Why this design is good:

- simple mental model
- works with current single-music export pipeline
- strong user value
- keeps V1 focused and shippable

Product framing:

- `Combined Soundtrack` is a lightweight playlist-to-soundtrack tool inside FluxCut:
  - import multiple songs
  - arrange them
  - merge them
  - preview them
  - use them in your video

## Caption look (Normal vs Stylish)

User-facing control:

- **Video → Final Mix → Include Captions** must be on (and mode is not pure **Video**).
- **Caption look** segmented control: **Normal** | **Stylish**.
- Changing style marks preview/final renders dirty; user rebuilds to see it in the file.
- **Script → Current Caption** preview approximates the chosen look (Stylish uses a small dim chip behind text so white type is visible on the light script card; **exported video** does not use that chip for Stylish—only the real render pipeline).

Implementation:

- **`VideoExporter.CaptionStyle`**: `normal`, `stylish`.
- **`AppViewModel.captionStyle`** passed into **`exportVideo(..., captionStyle:)`** for final exports (preview path keeps captions off as today; when captions are off, style is ignored).
- **Script → Speed** (`selectedNarrationSpeed`): **`exportVideo(..., speechRateMultiplier:)`** must match the Script tab so **`VideoExporter.synthesizeNarrationIfNeeded`** uses **`SpeechVoiceLibrary.makeUtterance(..., speechRateMultiplier:)`** for fresh TTS (not only the default `1.0`). When export **reuses** preview narration audio + cues (`externalNarrationAudioURL` + `externalCues`), speed is whatever was baked into that preview file.

### Normal

- **Intent:** YouTube-like, calm, always readable on varied footage.
- **Type:** system **semibold**, white fill, auto-fit font size from layout (same base scale as before Stylish existed).
- **Chrome:** semi-transparent **black rounded rectangle** behind the text block (not necessarily full video width—width follows measured text + padding). Corner radius **32** (scaled context).

### Stylish

- **Intent:** Reader-friendly, larger type for social/editorial feel; still legible on **bright** backgrounds.
- **Type:** **~1.5×** the same **base** font size as Normal (then same shrink-until-fits loop). **SF Rounded + bold** (`UIFontDescriptor.withDesign(.rounded)`), with extra **line spacing** for multi-line comfort.
- **Chrome:** **Tight** dim plate only behind the caption block (corner radius ~12–18 scaled)—**not** a full-width bar. Plate alpha ~**0.40** black so white type survives light floors/sky.
- **Outline / fill (important for CJK):** a **single** attributed string with **negative** `strokeWidth` makes strokes eat into glyphs and text reads **grey**. Stylish therefore uses a **two-pass** draw everywhere captions are rasterized:
  1. **Outline pass:** `foregroundColor` **clear**, **positive** `strokeWidth`, black stroke.
  2. **Fill pass:** **pure white** fill, no stroke, light `NSShadow`.
- **Paths:** both **slideshow frame draw** (`drawCaption` → `UIGraphics`) and **caption burn** (`makeAnimatedCaptionLayer` → two **`CATextLayer`** sublayers: outline under fill).

### Product rules

- **Normal** remains the default for users who want the classic pill.
- **Stylish** trades a bit of minimalism (adds a tight plate) for contrast on white/grey video content; the **fill** stays true white by construction (two-pass), not “dirty white” from combined stroke+fill.

## Smooth Media And Caption Design

- smooth media composition works
- captions can be added afterward with a caption-burn step
- that combination is working on tested mixed-media `Story` cases

Important conclusion:

- smooth path itself is not the problem
- smooth path plus caption burn is a valid solution

Important caution:

- this is proven for the mixed-media `Story` cases already tested
- it is not automatically proven for every possible project shape

## Music Library

Music Library design:

Selection:

- each music row supports toggle selection
- first tap: select
- second tap: de-select
- multiple tracks can be selected at once
- selected rows are highlighted

Preview:

- row play icon remains for preview
- row tap is only for select/de-select
- preview and selection stay separate

Top actions:

- `+` = add selected tracks
- `Exit` = close Music Library

Add behavior:

- if one or more tracks are selected:
  - tapping `+` adds all selected tracks to the project soundtrack queue
  - then Music Library closes
- if no tracks are selected:
  - `+` has no effect

Exit behavior:

- tapping `Exit` always closes Music Library
- `Exit` never adds music
- if tracks are selected but user taps `Exit`, selection is discarded

State:

- selection is temporary
- closing library clears current selection
- reopening starts with no selected tracks

Resulting UX:

- select one or more tracks
- tap `+` to commit them into the project
- tap `Exit` to leave without adding

Design note:

- `Exit` is clearer than `Enter` for this workflow

## Script Cleanup

Script cleanup design:

- the Script tab gets a one-tap `Clean Up` action before TTS or render
- cleanup is meant to normalize messy pasted script text without trying to rewrite the script itself

Current cleanup targets:

- stray leading punctuation such as a leading `.`
- leading numbering such as `1.`, `1)`, `(1)`
- Chinese outline prefixes such as `一、`, `二、`, `甲、`
- runs of extra newlines collapsed to a single blank-line paragraph separator (`\n\n`)
- extra spaces inside a line
- lines that are only dot-like characters (any length), such as `......` or `……`, removed entirely (including spaced dots like `. . .` and NBSP/ZWSP/BOM from paste)
- in-sentence runs of three or more `.` / `．`, or runs of Unicode ellipsis characters (`…` `⋯` `‥`), replaced with `, ` (with comma collapse when a comma already precedes the run); runs touching digits on both sides are left alone for decimals
- dot-run normalization uses dot-equivalent weight rather than raw character count, so visually equivalent forms such as `...`, `....`, `.....`, `…`, `……`, and mixed dot-like runs are handled consistently
- existing paragraph-ending punctuation must not be doubled, even when trailing spaces are present
- the final sentence of the article should receive a terminal punctuation mark if it is missing one
- **Edit Story / `StoryScriptPartition.nonEmptyParagraphs`**: paragraphs are delimited by **blank lines** (`\n\n`). Cleanup normalizes line endings, turns whitespace-only lines into paragraph breaks, collapses runs of three or more newlines to `\n\n`, and **if the script already has blank-line paragraph breaks**, keeps each chunk as one paragraph (single newlines inside a chunk remain line breaks within that paragraph). **If there are no blank-line breaks** (e.g. hard-wrapped paste with only `\n`), each cleaned non-empty line becomes its own paragraph (`\n\n` between lines) so blocks can be assigned.
- after cleanup, `reconcileStoryEditBlocksWithScript()` runs so block ranges stay valid when paragraph count changes

Pause behavior:

- if a title-like line is missing ending punctuation before the next non-empty line, cleanup inserts a pause-ending mark
- Chinese lines use `。`
- other lines use `.`

Product intent:

- reduce unwanted TTS pauses from messy prefixes
- restore missing pauses between title-style lines and the next sentence
- make pasted legal or outline-style text more narration-friendly before playback

UI behavior:

- after cleanup, the keyboard is dismissed
- the script view returns to the beginning so the cleaned text can be reviewed quickly

Important scope note:

- cleanup is conservative for wording (no paraphrase or translation)
- it normalizes common TTS-breaking patterns and **paragraph boundaries** for Edit Story as above

## Script Preview Controls

Script preview controls design:

- the preview tool is optional, not always visible
- the Script tab should keep more editing space unless the user explicitly wants preview tools

Control model:

- `Preview` is a toggle
- tap `Preview` to show the preview tool
- tap `Hide Preview` to close it again
- hiding the preview tool also stops active preview playback

Layout simplification:

- `Top` and `Bottom` quick-jump buttons are removed
- `Clean Up` sits on the same row as `Preview`

Product framing:

- editing and cleanup are the primary Script-tab tasks
- preview tools should be available when needed, but not consume space by default

## Media Duplicate And Delete

Media duplicate and delete design:

- the large media preview window `...` menu supports per-item management
- `Duplicate` and `Delete` live in that menu
- duplicate is immediate
- delete requires confirmation

Duplicate behavior:

- duplicating inserts the new media item immediately after the current one
- the duplicate is reference-only, not a physical copy of the source file
- the duplicate gets a new app-level identity, but points to the same underlying photo or video asset
- this keeps duplication fast and avoids extra storage usage

Numbering behavior:

- duplicates use source-aware labels such as `#3A`, `#3B`
- the original item keeps its base label such as `#3`
- later unrelated media keep their own base numbering
- this avoids a disruptive full renumbering of the whole sequence just because one item was duplicated

Timing behavior:

- duplicated videos keep the same natural duration as the original source clip
- duplicated photos are treated as another instance of the same photo in the timeline
- timing mode rules still apply normally during render

Delete behavior:

- `Delete` removes the currently selected media item from the project
- delete is confirmed before execution
- the confirmation message identifies the item using its visible label, such as `#3A`

Sync behavior:

- duplicate, delete, reorder, and Import Media must stay in sync
- Import Media reflects unique underlying source assets, not every visible duplicate entry
- removing one duplicate does not remove the shared source asset if another copy is still in the project

Product framing:

- duplicate is a timeline tool, not a file-copy tool
- delete is destructive and should be guarded
- media management should stay fast, predictable, and sequence-aware

## Default branch and near-final merge

- FluxCut’s integration line is **`main`**. GitHub **`origin/HEAD`** points to **`origin/main`**; this repository does **not** use a **`master`** branch name on the remote.
- **2026-04-12:** branch **`story_enhance`** was merged into **`main`** and pushed (`Merge branch 'story_enhance' into main (near-final narration/caption work)`). Treat **`main`** as the shipping line for this near-final product phase.
- For a durable record of “where Git points,” after pulling: **`git rev-parse HEAD`** with **`main`** checked out should match the current tip of **`origin/main`** (see **`docs/GIT_PUSH_LOG.md`** for the merge commit hash recorded at merge time).

## Narration preview vs final export

- **Script → narration preview** builds seekable audio and cues inside **`NarrationPreviewBuilder`**. To keep long scripts responsive, preview may **merge** many small utterances into fewer **`AVSpeechSynthesizer.write`** passes (cap **36** segments after the existing preview duration cap; merged chunk length capped at **4000** characters) and applies a **90 second** timeout per segment so the UI never waits indefinitely on a stuck synthesizer.
- **Final video export** uses **`VideoExporter`** and the full narration segmentation pipeline: it does **not** apply the preview-only merge batching or the preview synthesis timeout. Caption chunking still shares **`CaptionTextChunker`** / voice tags with preview where designed, but **timing and utterance boundaries** for export follow export rules, not the preview guardrails.
- **Product intent:** preview is for quick iteration and sync checks; export remains the authoritative render for length, segmentation, and burned captions.
