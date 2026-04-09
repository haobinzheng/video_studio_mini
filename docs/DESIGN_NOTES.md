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
- repeated blank lines
- extra spaces inside a line

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

- cleanup is conservative
- it normalizes common TTS-breaking patterns
- it is not intended to paraphrase, translate, or structurally rewrite the script

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
