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
