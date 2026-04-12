# FluxCut Git Push Log

Use this file to record important Git push checkpoints and branch/tag history.

## Master Branch Log

### Production v1

I created the tag:

- `production-v1-2026-04-02`

It points to the current stable commit on `main`, so we now have a clean reference for:

- Production version 1
- date `2026-04-02`
- commit `f7e8f03`
- tag `production-v1-2026-04-02`

## Log

### Concept 1

- `Flow Ribbon`
- one continuous ribbon sweeping diagonally, with a subtle cut/change in direction
- feels smooth, modern, and creator-focused
- best if you want FluxCut to feel elegant and premium

Color:

- amber
- coral
- deep ink blue background/accent

### Concept 2

- `Cut Ribbon`
- a folded ribbon with one sharper slice through it
- suggests editing, shaping, and momentum without looking like a film tool
- best if you want a stronger `creation + cutting` identity

Color:

- warm orange
- copper coral
- dark teal accent

### Concept 3

- `Hidden F Ribbon`
- abstract ribbon shape that quietly forms an `F`
- more brand-like and ownable
- best if you want the logo to feel like a true product mark, not just a symbol

Color:

- amber gold
- coral red
- muted navy or ink

Recommendation:

- `Concept 1` if you want softer and more premium
- `Concept 3` if you want stronger brand identity

Strongest pick for FluxCut:

- `Concept 3: Hidden F Ribbon`

It gives you:

- flow
- cut
- motion
- a recognizable brand mark

## Feature Branch Log

### 2026-04-02

Pushed to the remote feature branch.

Details:

- branch: `story_enhance`
- new commit: `3fcf02f`
- message: `Polish studio header and render status`

### 2026-04-03 09:00 PDT

Updated production tag:

- `production-v1-2026-04-03`

What changed:

- removed old tag: `production-v1-2026-04-02`
- created new official production tag at `main` commit `892b366`
- pushed the tag update to GitHub

Official record:

- `main` -> `892b366`
- `story_enhance` -> `d359d5e`
- production tag -> `production-v1-2026-04-03`

### 2026-04-03 23:00 PDT

Committed on `story_enhance`.

Details:

- branch: `story_enhance`
- commit: `d80211c`
- message: `Stabilize playback, storage cleanup, and video layout`

This checkpoint includes:

- in-app video playback sound fix
- automatic cleanup of stale copied media videos on media replacement
- the current `Video` mode horizontal-fit behavior
- the `Story` memory fix that reuses one video-audio composition track

### 2026-04-04 08:06 PDT

Details:

- branch: `story_enhance`
- new commit: `b6cc666`
- message: `Add settings cleanup tools and header controls`

### 2026-04-04 10:30 PDT

Pushed to the feature branch.

Details:

- branch: `story_enhance`
- new commit: `642bcc8`
- message: `Add source-preserving controls for video mode`

### 2026-04-04 12:49 PDT

Details:

- branch: `story_enhance`
- new commit: `b28432c`
- message: `Apply source-preserving render sizing to real-life mode`

### 2026-04-04 15:14 PDT

Details:

- branch: `story_enhance`
- new head: `e47e41a`
- message: `Refine music library and storage settings`

### 2026-04-04 16:49 PDT

Details:

- branch: `story_enhance`
- new head: `4fbff98`
- message: `Add tree-based FluxCut branding`

### 2026-04-04 23:27 PDT

Details:

- branch: `story_enhance`
- new head: `0340563`
- message: `Refine slideshow and story rendering profiles`

This checkpoint includes:

- `Slideshow` timing and export-window behavior
- the `4K 60 High` safety rule for narration-longer slideshow exports
- smoother video-style profile for `Story`
- the recent UI wiring needed for those mode changes

### 2026-04-05 14:28 PDT

Details:

- branch: `story_enhance`
- new head: `1f5e38f`
- message: `Honor manually selected narration voices`

This preserves the single-voice selection fix on the repo.

### 2026-04-06 16:26 PDT

Details:

- branch: `story_enhance`
- new head: `8f07b94`
- message: `Refine music library and narration validation`

This checkpoint includes:

- Music Library workflow improvements
- import feedback and duplicate handling
- extract soundtrack flow cleanup
- narration language mismatch blocking
- script keyboard dismissal cleanup

### 2026-04-06 21:55 PDT

Details:

- branch: `story_enhance`
- new head: `c269907`
- message: `Protect music library during cleanup`

### 2026-04-08 08:14 PDT

Details:

- branch: `story_enhance`
- new head: `315dca1`
- message: `Improve story caption-off media planning`

This milestone includes:

- the new `Story/caption off` photo-time rules
- preflight blocking when computed photo time exceeds `20s`
- status-window guidance before render starts

### 2026-04-08 10:28 PDT

Details:

- branch: `story_enhance`
- new head: `7fe150f`
- message: `Add smooth mixed-media story captions`

This milestone includes:

- `Story + captions on + mixed media` using smooth base composition plus a caption-burn step
- photo-only `Story + captions on` keeping the frame-by-frame renderer
- bottom-positioned captions in the smooth caption-burn path
- narration-prep progress updates instead of looking stuck at `8%`
- photo-only caption-on `Story` using a `5s` minimum with no photo looping

### 2026-04-08 10:58 PDT

Details:

- branch: `story_enhance`
- new head: `d9b152c`
- message: `Add slideshow captions and slower photo pacing`

This checkpoint includes:

- `Slideshow` captions using the same smooth base plus caption-burn approach
- `Include Captions` enabled for `Slideshow`
- all-photo `Slideshow` pacing changed from `3s` to `8s` per photo

### 2026-04-08 12:54 PDT

Details:

- branch: `story_enhance`
- new head: `9d414bd`
- message: `Fix rendered video playback restore`

This checkpoint includes:

- Video tab playback surviving tab switches
- rendered caption-burn videos no longer getting shifted into the corner during playback

### 2026-04-08 17:47:33 PDT

Details:

- branch: `story_enhance`
- new head: `f269f05`
- message: `Improve music library multi-select add`

This checkpoint includes:

- Music Library multi-select toggle behavior
- `+` adding all selected tracks and closing the library
- `Exit` closing without adding
- only one selected row acting as the active preview/play row at a time

### 2026-04-08 18:30 PDT

Details:

- branch: `story_enhance`
- new head: `61972fa`
- message: `Improve media item management`

This checkpoint includes:

- per-item media delete moved into the upper preview-stage `...` menu
- media delete syncing with `Import Media`
- media drag reorder syncing with `Import Media`
- new docs:
  - `docs/GIT_PUSH_LOG.md`
  - `docs/DESIGN_NOTES.md`

### 2026-04-08 21:12 PDT

Details:

- branch: `story_enhance`
- new head: `a6bcaed`
- message: `Add script cleanup action`

This checkpoint includes:

- Script-tab `Clean Up` action for narration text
- removal of stray leading punctuation before TTS
- removal of leading numbering such as `1.`, `1)`, and Chinese outline prefixes like `一、`
- automatic title-style pause punctuation, using `。` for Chinese lines
- repeated blank lines collapsed to a single blank line
- cleanup dismissing the keyboard and scrolling back to the top of the script

### 2026-04-08 21:32 PDT

Details:

- branch: `story_enhance`
- new head: `63e6e39`
- message: `Refine script preview controls`

This checkpoint includes:

- Script `Preview` becoming a show or hide toggle for the preview tool
- `Top` and `Bottom` buttons removed from the Script tab
- `Clean Up` moved onto the same row as `Preview`

### 2026-04-08 21:36 PDT

Details:

- branch: `story_enhance`
- new head: `f881208`
- message: `Update design notes`

This checkpoint includes:

- Script cleanup design notes
- Script preview control design notes

### 2026-04-09 10:23 PDT

Details:

- branch: `story_enhance`
- new head: `7f76ba7`
- message: `Fix script cleanup punctuation handling`
- status: `local only, not pushed`

This checkpoint includes:

- script cleanup no longer duplicating Chinese paragraph-ending `。`
- final line cleanup adding missing ending punctuation more reliably
- blank-line cleanup behaving consistently across paragraphs
- trailing-space and full-width-space handling tightened for cleanup

### 2026-04-09 10:32 PDT

Details:

- branch: `story_enhance`
- new head: `accde57`
- message: `Update git push log`

This checkpoint includes:

- pushed the local script cleanup punctuation fix to the remote branch
- recorded the latest local cleanup fix and log update on the branch

### 2026-04-09 23:36 PDT

Details:

- branch: `story_enhance`
- new head: `f101458`
- message: `Improve media append flow`

This checkpoint includes:

- trailing `+` add-media tile in the media thumbnail row
- append-only media loading instead of reloading the full existing selection
- already imported media showing as selected when opening the append picker
- improved `+` tile alignment in the media row

### 2026-04-10 22:50 PDT

Details:

- branch: `story_enhance`
- new head: `a7474f4`
- message: `Add media duplicate controls`

This checkpoint includes:

- Media `...` menu adding `Duplicate` alongside `Delete`
- duplicate entries using source-aware labels like `#3A`
- duplicate implemented as a reference-only timeline copy, not a physical asset copy
- Media and Import Media sync updated to track unique underlying source assets
- delete confirmation added for media items, while duplicate remains instant

### 2026-04-11

Pushed to the remote feature branch.

Details:

- branch: `story_enhance`
- new head: `96488a0`
- message: `Story smooth export, faster Photos import, safer large-file copy`
- remote: `origin` (`github.com:haobinzheng/video_studio_mini.git`)

This checkpoint includes:

- **Story / video:** `Story` timelines that contain **only videos** use the **smooth** composition + export path (including **preview**); **Story + video + captions** uses the same smooth base plus caption-burn instead of per-frame `AVAssetImageGenerator` slideshow rendering (avoids jetsam on long/large clips).
- **Media import:** `PhotosPicker` wired with `photoLibrary: PHPhotoLibrary.shared()` so `itemIdentifier` resolves and imports reference **PHAsset** + duration instead of exporting the full movie up front; parallel per-item load; `URL` before `PickedMovie` when resolving files; move/stream copy helpers (no `Data(contentsOf:)` for huge files); optional background completion for file-backed placeholders; append flow `combinedSelection` + duplicate-append fix; deferred small local thumbnails for library videos.
- **Assets:** `AppIcon-1024.png` resized to **1024×1024** for the marketing icon slot.
- **Build:** `FileHandle.read(upToCount:)` optional `Data?` handling for newer SDKs.

### 2026-04-11 (narration/caption sync + log)

Pushed to the remote feature branch.

Details:

- branch: `story_enhance`
- remote: `origin` (`github.com:haobinzheng/video_studio_mini.git`)
- primary (feature) commit: `a97bd5d` — `Fix narration and caption sync for preview and export`

Smaller follow-up commits on the same branch may only update this log file; use `git log origin/story_enhance` for the current tip.

**`a97bd5d` — caption sync**

- Remove **1.9×** narration duration bias; caption timing follows **measured TTS** length.
- **Unified** on-screen lead (`SubtitleTimelineEngine.displayLeadSeconds`) for **preview** and **burned** captions.
- **Aligned** preview vs export **caption chunking** (`NarrationPreviewBuilder` ↔ `VideoExporter`).
- **Subtitle lookup** holds the previous cue across **gaps** between cue times; removed unused `index(at:)`.

Later commits on the same branch may only touch `docs/GIT_PUSH_LOG.md` to record pushes; see `git log` for the exact tip after those updates.

### 2026-04-11 (NLTokenizer caption chunking)

Pushed to the remote feature branch.

Details:

- branch: `story_enhance`
- remote: `origin` (`github.com:haobinzheng/video_studio_mini.git`)
- use `git log origin/story_enhance` for the current tip (this section may be followed by log-only commits)

Commits for this feature line:

1. `6146603` — `Caption chunking: NLTokenizer + punctuation hierarchy for CJK/JA`
2. `8eb3faf` — `docs: log NLTokenizer caption chunking push 6146603`

**`6146603` — caption chunking**

- New **`CaptionTextChunker.swift`**: **`NLTokenizer`** (on-device `NaturalLanguage`) for **zh / ja / ko / th / lo** and related voice tags; shared by **`NarrationPreviewBuilder`** and **`VideoExporter`**.
- **`SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier:)`** for tokenizer language selection.
- **Chinese & Japanese:** preprocess with **sentence / clause / light punctuation** boundaries, then tokenizer; tighter line limits; merge very short **tail** caption fragments.
- **Latin / English:** unchanged **legacy** splitting (whitespace + word caps).

**`8eb3faf`+**

- **`GIT_PUSH_LOG.md`** updates for this NLTokenizer checkpoint (and any later log-only commits on the same branch).

### 2026-04-12 (Caption look: Normal / Stylish)

Pushed to the remote feature branch.

Details:

- branch: `story_enhance`
- remote: `origin` (`github.com:haobinzheng/video_studio_mini.git`)
- use `git log origin/story_enhance` for the current tip (this section may be followed by log-only commits)

**Caption look**

- **`VideoExporter.CaptionStyle`** (`Normal` / `Stylish`) and **`AppViewModel.captionStyle`**; **Video** tab segmented control + Script **Current Caption** preview styling.
- **Normal:** semibold white on soft rounded pill (existing YouTube-like look).
- **Stylish:** ~**1.5×** base size, **SF Rounded bold**, extra line spacing, **tight dim plate** (~40% black) for light backgrounds; **two-pass** outline then **pure white** fill (plus `CATextLayer` pair for burn-in) so CJK does not read grey.
- Design record: **`docs/DESIGN_NOTES.md`** section **Caption look (Normal vs Stylish)**.
