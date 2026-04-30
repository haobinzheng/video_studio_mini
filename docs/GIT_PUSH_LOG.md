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

### 2026-04-26 — Pushed: `pro-version` @ `b423343` (Script tab: fold long instructions into disclosures)

- **Git:** `git push origin pro-version` — `ae90b10..b423343` (this doc and **DESIGN_NOTES** updated **locally** after the push, per repo policy; not in this push).
- **Summary:** **Script tab cleanup:** converted three long always-visible instruction blocks into collapsible **`DisclosureGroup`** sections with persisted **`@AppStorage`** state, matching the Pro tab’s “How assigning works” pattern. This keeps guidance available on demand while reducing visual clutter during normal script editing. **Keys:** `fluxcut.scriptIntroHelpExpanded`, `fluxcut.scriptReloadVoicesHelpExpanded`, `fluxcut.scriptHideVoicesHelpExpanded`. **File:** `CapcutApp/ContentView.swift`.

### 2026-04-26 — Pushed: `pro-version` @ `ae90b10` (TTS number parsing tighten-up: percent/range/thousands)

- **Git:** `git push origin pro-version` — `6a27a5e..ae90b10` (this doc and **DESIGN_NOTES** updated **locally** after the push, per repo policy; not in this push).
- **Summary:** **`SpeechVoiceLibrary.textForSpeechSynthesis`** hardening for multilingual numeric speech: (1) `%` rewrite for Chinese/Japanese/Korean decimal percents so fractions are read digit-by-digit (`2.234%`), (2) numeric-range rewrite now supports optional `%`/`％` on both sides so Cantonese does not read `-` as minus in `2.235%-2.345%`, (3) English-style thousands stripping (`1,234,343` → `1234343`) for a selected locale set including **en**, with strict grouping validation so malformed forms like `1,3434,343` are not normalized.

### 2026-04-26 — Pushed: `pro-version` @ `6a27a5e` (Music Library: Pro one-level folders; Add in bottom bar for search)

- **Git:** `git push origin pro-version` — `2ed38b3..6a27a5e` (this doc and **DESIGN_NOTES** updated **locally** after the push, per repo policy; not in this push).
- **Summary:** **Music Library (Pro):** one-level user folders under **`Documents/FluxCutMusicFolders/<name>/`**; imports also at **Documents** root = **Unfiled**; **stable** library **`id`** from relative path (SHA-256) so folder moves do not break references; **All / Unfiled / folder** scope, **context Move**, **New folder** / **Rename folder** / **Delete empty** (toolbar folder menu), rename/move tracks with soundtrack URL + optional combined-bed rebuild. **`performCurrentProjectCleanup`** protects the folder tree. **Gated** by **`isEditStoryProEnabled`**. **Music Library UI:** **Add** (`+`) moved from the navigation **trailing** bar to the **bottom safe-area** bar next to **Import** / **Extract** so it stays available when **`.searchable`** is active (iOS often hides trailing toolbar items during search). **Files:** `CapcutApp/AppViewModel.swift`, `CapcutApp/ContentView.swift`.

### 2026-04-26 — Pushed: `pro-version` @ `2ed38b3` (Music Library import, extract overlay, narration chunking)

- **Git:** `git push origin pro-version` — `62296ac..2ed38b3` (this doc and **DESIGN_NOTES** updated **locally** after the push, per repo policy; not in this push).
- **Summary:** **Music Library — Import from Files:** synchronous security-scoped access + copy in the `fileImporter` result handler (`ingestPickedFilesIntoMusicLibraryFromFileImporter`), then main-actor **`reloadMusicLibraryFromDisk()`** (replaces **`refreshMusicLibrary`** early-return that could skip reload). **Removed** the post-share “Import to Music Library?” prompt for extracted soundtracks (unreliable). **Extract Soundtracks:** full-screen dimmed overlay with **`ProgressView`** + **`statusMessage`** on the Music Library sheet while video loads and audio extracts, before the system Save/share sheet. **`CaptionTextChunker` / `PreviewNarrationSegmentBudget` / `WatermarkSettingsDetailView`:** small fixes. **Files:** `CapcutApp/AppViewModel.swift`, `CapcutApp/ContentView.swift`, `CapcutApp/CaptionTextChunker.swift`, `CapcutApp/PreviewNarrationSegmentBudget.swift`, `CapcutApp/WatermarkSettingsDetailView.swift`, `CapcutApp.xcodeproj/project.pbxproj`.

### 2026-04-25 — Pushed: `pro-version` @ `62296ac` (TTS: decimals, $ amounts, ranges, voice-locale)

- **Git:** `git push origin pro-version` — `87ffcef..62296ac` (this doc and **DESIGN_NOTES** updated **locally** after the push, per repo policy; not in this push).
- **Summary:** `AVSpeechSynthesizer` treated `.` in numbers as phrase breaks; `chunkedText` also split on `.` and broke `2.6` into two utterances. **Fixes:** (1) **Narration chunking** — `narrationPiecesByPunctuationPreservingDecimalPoints` does not treat ASCII `.` as a break when it sits between two digits (so `$2.6` stays one segment). (2) **`textForSpeechSynthesis`** — voice BCP-47–aware decimal/currency words; comma-decimal locales; **$** + scale (Billion/Trillion, capture group fix); **spaced fraction digits** so `3.45` is not read as “forty-five”; **numeric ranges** `2.3-3.5` / `$2.3-$3.5` → localized connector (e.g. `to` / `到`). **Files:** `CapcutApp/AppViewModel.swift` (`SpeechVoiceLibrary`), `CapcutApp.xcodeproj/project.pbxproj`.

### 2026-04-24 — Pushed: `pro-version` @ `87ffcef` (1B: force light UI when iPhone is in Dark Mode)

- **Git:** `git push origin pro-version` — `c5e060b..87ffcef` (this doc updated **locally** after the push, per repo policy; not in this push).
- **Summary:** TestFlight found **illegible UI** (white/light semantic text on light cards) when the device used **Dark Mode**. **1B (defer full 1A):** `Info.plist` → **`UIUserInterfaceStyle` = `Light`**, and **`FluxCutApp`** root `ZStack` → **`.preferredColorScheme(.light)`** so the app always presents as **light** while the user can keep a dark system for other apps. **Files:** `CapcutApp/Info.plist`, `CapcutApp/FluxCutApp.swift`.

### 2026-04-22 — Pushed: `pro-version` @ `5237390` (4K Video/Slideshow: resolution math + full-frame upscale; README; Privacy manifest)

- **Git:** `git push origin pro-version` — `40d7f4a..5237390` (this doc updated **locally** after the push, per repo policy; not in this push).
- **Summary — root cause of “4K but small” (see commit body for full detail):**
  1. **Output pixel size:** Per-axis `min(merged, user)` and similar could shrink below the chosen resolution. In `outputSizeFittingUserResolution`, `t = min(1, capLong / longIn)` **blocked upscaling** the stitch to the user’s long edge, so dimensions could stay tiny. **Slideshow** `effectiveSlideshowExportSettings` now uses aspect-guarded `max` + uniform `outputSizeFittingUserResolution` (not per-axis `min`). **Photo-only Slideshow** no longer caps at ~2560 when **`videoModeSettings`** is set: user resolution floor + same fitting path + user frame rate. **`resolvedRenderProfile` (Video)** uses `exportVideoStitchOutputSize` for consistency with export. **Same-aspect branch** in `outputSizeFittingUserResolution` returns the scaled `s` from cover+contain (not a wrong `evenPixelSize(uw,uh)`).
  2. **Small picture inside a big frame:** `fittedTransform` with `preserveSourceScale: true` used `scale = min(fitScale, 1)`, so source was **never upscaled**; 720p appeared as a small inset in a 4K output. **Fix:** `preserveSourceScale` is **true** only when `videoModeSettings == nil` (preview) for **Video stitch** and **`exportRealLifeComposition`** (smooth Slideshow/Story); final export with user resolution allows upscale to **fill** the output (aspect-fit).
- **Also in commit:** root **`README.md`**, **`CapcutApp/PrivacyInfo.xcprivacy`** added to the app target, minor **`AppViewModel` / `ContentView`** copy or wiring.

### 2026-04-22 — Pushed: `pro-version` @ `40d7f4a` (Edit Story assign sheets: copyable Block script + Segment script)

- **Git:** `git push origin pro-version` — `d9fc169..40d7f4a` (this doc updated **locally** after the push, per repo policy; not in this push).
- **Summary:** **`ContentView`:** `.textSelection(.enabled)` on **`Text(assignSheetBlockScriptText)`** (media **Block** assign full-screen) and **`Text(musicAssignSheetScriptText)`** (music **Assign segment** sheet) so users can select and **Copy** script text (e.g. for search or notes).

### 2026-04-22 — Pushed: `pro-version` @ `d9fc169` (FCS candidate v1: FluxCut, Pro IAP, intros, video URL invalidation)

- **Git:** `git push origin pro-version` — `45b432b..d9fc169` (this doc and **DESIGN_NOTES** updated **locally** after the push, per repo policy; not in this push).
- **Summary:** **FCS candidate v1** — app entry **`FluxCutApp`**, **StoreKit 2** Pro (`ProEntitlementManager`, non-consumable), **shared scheme** + root **`FluxCut.storekit`**, export names **`fluxcut-mini-*`**, **Info** / copy **FluxCut**. **Introduction:** ~800w basic / ~extended Pro default scripts; free-tier **caption** under script removed from UI. **Pro** card: no **price** on screen (sheet shows it). **Bugfix:** `clearRenderedVideoFileReferencesIfPresent` when **media** or **soundtrack** changes so `exportedVideoURL ?? videoPreviewURL` does not show a stale final over a new preview. **`WatermarkSettingsDetailView`** touch.

### 2026-04-22 — Pushed: `pro-version` @ `45b432b` (Pro watermark: settings, export, sizing, mark strength)

- **Git:** `git push origin pro-version` — range `328e4f5..45b432b` (this doc updated **locally** after the push; not part of that push, per repo doc policy).
- **Summary:** **Settings → Video → Watermark** with **`WatermarkSettingsDetailView`**: text vs image, **mark strength** (10–100% of layer opacity; default **0.85** for new prefs), **size** scale (~35–400% of resolution-based default), **position** corners, import PNG, style preview (overlay alignment). **Pro gate:** `isEditStoryProEnabled` + `reconcileProWatermarkGate`; export uses `videoWatermarkSettingsForExport()`. **`VideoExporter`:** `WatermarkSettings` with `sizeScale`, text/image layout, image **drop shadow** for contrast, **upscale** small sources to target span (removed `min(…,1)` cap), tighter **safe padding**, **~70px@1080**-relative base and frame-relative max span. **ContentView** row shows Pro vs On/Off.

### 2026-04-21 — Pushed: `pro-version` @ `328e4f5` (Script intro, settings support, free-tier, export invalidation)

- **Git:** `git push origin pro-version` — range `a3f349e..328e4f5` (this doc updated **locally** after the push; not part of that push, per repo doc policy).
- **Summary:** Longer default **Script** / **Introduction** copy (~6 min read, under Latin free word cap). **Settings → About** line for sharing in **Video** / **Slideshow** with or without script. **Free tier:** non-Latin script cap **1800** characters (was 1200). **Voice:** auto-pick first voice for language; **`markAllVideoRendersDirty`** clears stale **`videoPreviewURL`** / **`exportedVideoURL`**. New **`SettingsSupportViews.swift`**; **`.gitignore`**: `web3forms_key`, **`.build/`**.

### 2026-04-20 — Slideshow: center portrait video in 16:9 frame (fix left-heavy letterbox)

- **Change:** **`VideoFrameCache`** uses a **square** **`maximumSize`** (max of render edges) instead of the 16:9 **`renderSize`** so **`AVAssetImageGenerator`** does not embed 9:16 frames in a wide padded bitmap; **`centeredAspectFitRect`** replaces **`AVMakeRect`** for explicit centering using **`cgImage`** pixel dimensions.
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Preview export: enforce ~20s cap after full-length narration prep

- **Change:** Preview runs always **`timelineSegmentsTrimmed`** to **`resolvedDuration`**; **`AVAssetExportSession.timeRange`** set in **`mergeAudioAndVideo`**, **`exportStitchedComposition`**, and smooth-story **`exportRealLifeComposition`** so muxed narration cannot extend output past the video timeline (fix: second “preview” exporting full length after final export with unchanged script).
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Edit Story on: compact sentence-aligned caption lines

- **Change:** **`sentenceAlignedCaptionDisplayText`** gains **`phraseRows`** vs **`compactLines`**. Prepared / Edit-off keeps **`phraseRows`**; **`sentenceAlignedTimedCaptionSegments`** (Edit on) uses **`compactLines`** so exports avoid many stacked short phrase rows on long utterances.
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Auto-rebuild narration preview when cue timing policy changes

- **Change:** **`AppViewModel.narrationPreviewCueTimingPolicy`** (mirrors segmentation policy). **`needsPreviewRefresh`** forces **`prepareNarrationPreview`** if the built policy token does not match, so final export does not reuse stale cues after timing algorithm updates; users do not need to manually “preview again.”
- **Files:** `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Sentence-aligned captions: utterance-accurate timing (fix Edit-off drift)

- **Change:** **`NarrationPreviewBuilder.buildSentenceAlignedCues`** and **`VideoExporter.sentenceAlignedTimedCaptionSegments`** no longer extend each window with **`max(utterance, minimum)`**; timing follows measured TTS length so prepared-preview export stays in sync with muxed narration.
- **Files:** `CapcutApp/NarrationPreviewBuilder.swift`, `CapcutApp/VideoExporter.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Export: sentence-aligned external cues use Edit-on caption path

- **Change:** **`VideoExporter.sentenceAlignedCaptionDisplayText`** shared by **`sentenceAlignedTimedCaptionSegments`** and **`captionSegments(from:externalCues:)`**. Sentence-aligned voices no longer run **`formattedCaptionText`** on full preview cue strings; non–sentence-aligned unchanged.
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Preview narration: oversized single segment respects duration cap

- **Issue:** With **`maximumDuration`** set (e.g. quick video preview), **`cappedPreviewSegments`** always appended the **first** segment even when its **estimated** duration alone exceeded the cap (one long paragraph → one huge TTS segment). **`applyPreviewNarrationSynthesisBudget`** skipped when **`segments.count == 1`**, so preview export could synthesize far more than the ~preview-window budget.
- **Change:** Added **`PreviewNarrationSegmentBudget.splitToFitEstimatedBudget`** ( **`narrationSegments`** + greedy prefix binary search). **`NarrationPreviewBuilder.cappedPreviewSegments`** expands segments before accumulating; **`VideoExporter.applyPreviewNarrationSynthesisBudget`** expands then prefixes (no early return for single segment). Preview is still **honored**—it uses a **bounded prefix** of the script, not silence.
- **Files:** `CapcutApp/PreviewNarrationSegmentBudget.swift`, `CapcutApp/NarrationPreviewBuilder.swift`, `CapcutApp/VideoExporter.swift`, `CapcutApp.xcodeproj/project.pbxproj`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-20 — Captions: sentence-aligned export matches preview (Edit Story vs whole-script)

- **Issue:** With **Chinese** (sentence-aligned narration), **Edit Story** final export could show **more** on-screen caption lines than **Edit Story off**, because block export **bypasses** preview subtitle cues and **`VideoExporter.sentenceAlignedTimedCaptionSegments`** used **`formattedCaptionText` per line** (requires ASCII space before balancing), while preview used **`displayCaption`** (balance without that guard)—different line counts from the same `splitForCaptions` pieces.
- **Change:** Added **`CaptionTextChunker.displayCaptionLine`** (shared **`balancedCaptionLine`**); **`NarrationPreviewBuilder`** and **`sentenceAlignedTimedCaptionSegments`** both use it. **`VideoExporter`** empty fallback uses **`displayCaptionLine`** on normalized joined text.
- **Follow-up (same day):** Tried **`mergeSplitCaptionLinesToAtMostTwo`** to cap rows; reverted—merging tokenizer phrases into two dense lines hurt **perceived** narration–caption sync (phrase boundaries no longer matched speech). Kept **`displayCaptionLine`** parity only.
- **Files:** `CapcutApp/CaptionTextChunker.swift`, `CapcutApp/NarrationPreviewBuilder.swift`, `CapcutApp/VideoExporter.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-19 — Pushed: `pro-version` @ `95a9e04` (narration voices + Edit Story assign import)

- **Git:** `git push origin pro-version` — range `2263d96..95a9e04`.
- **Summary:** Narration voice list lists **Enhanced** and **Premium** only; in-app copy explains that **Siri** personas are not available to third-party `AVSpeechSynthesizer` on iOS; removed Siri bundle probing. **Edit Story → Assign:** the trailing **+** (PhotosPicker) still appends imports to the media pool and now also appends those new clips to **Assigned to this block** while the assign sheet is open; preview jumps to the last imported clip; Studio Tip text updated.
- **Files:** `CapcutApp/AppViewModel.swift`, `CapcutApp/ContentView.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Pushed: `pro-version` @ `cfad2a6` (export hardening + Edit Story preview/narration)

- **Git:** `git push origin pro-version` — range `5ea3b4f..cfad2a6`.
- **Summary:** Per-run **`RenderedVideos/<UUID>/`** workspaces; **`await exportVideo`** (no `Task.detached`) + **`awaitExportSession`** / **`cancelExport()`** on Stop; Edit Story preview TTS budget keeps one range per block; Edit Story full export reuses **`NarrationPreview/utterance-preview-*.caf`** when full-length prep is valid; **Stop** on preview clears narration cache (prior fix). **Docs:** `docs/DESIGN_NOTES.md` aligned with behavior.
- **Files (code):** `CapcutApp/AppViewModel.swift`, `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md`, `docs/DESIGN_NOTES.md`.

### 2026-04-16 — Edit Story: reuse `NarrationPreview` utterance CAFs on export (no duplicate 500+ TTS)

- **Issue:** **Edit Story** forced **`bypassNarrationPreviewAudio`**, so **`exportVideo`** always re-synthesized every utterance in **`RenderedVideos/<uuid>/`** even after **`prepareNarrationPreview`** had already produced the same segments in **`NarrationPreview/utterance-preview-*.caf`**. Stopping export and restarting repeated the full TTS pass.
- **Change:** When full-length narration preview is valid (**`narrationPreviewIsFullLength`** + Edit Story descriptor), pass **`prebuiltUtteranceSourceDirectory`** → **`VideoExporter`** copies prebuilt CAFs into the export workspace instead of calling **`renderUtteranceAudio`** per segment.
- **Files:** `CapcutApp/VideoExporter.swift`, `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Edit Story preview: fix `invalidStoryBlockPlan` after preview TTS budget

- **Cause:** **`applyPreviewNarrationSynthesisBudget`** used **`compactMap`** on per-block utterance ranges. Blocks whose utterances fell outside the preview prefix were **dropped**, so **`storyBlockUtteranceRanges.count` ≠ block count** → **`composeStoryBlockTimelineSegments`** threw **`invalidStoryBlockPlan`** (“Story block layout is invalid…”) even when the Edit tab was fully assigned.
- **Change:** Clip each block’s range to **`0..<prefix.count`** with **`map`** (preserve one range per block; use empty **`lo..<lo`** when a block has no utterances in the sample).
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Export: isolated workspace per session, structured await, AV cancel on Stop

- **Issue:** `Task.detached` for **`exportVideo`** ignored cancellation from **Stop** / new export; **`AVAssetExportSession`** kept running; **`RenderedVideos/capcut-mini-video.mov`** (and shared intermediates) could race across runs.
- **Change:** **`exportVideo(..., exportArtifactID:)`** writes under **`RenderedVideos/<UUID>/`** (final + intermediates). **`AppViewModel`** awaits **`exportVideo`** in the same task as narration prep (no detached). **`awaitExportSession`** wraps **`export`** with **`withTaskCancellationHandler`** → **`cancelExport()`** on task cancel. Sparse **`Task.checkCancellation()`** between major phases. Removed **`activeVideoExportTask`**.
- **Files:** `CapcutApp/VideoExporter.swift`, `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Stop preview: invalidate narration cache so full export rebuilds

- **Issue:** After **Stop** on a stuck **preview** render, the next **final** export could skip **`prepareNarrationPreview`** (`needsPreviewRefresh` false) and jump straight into **`VideoExporter`** (merge / in-exporter narration), because cached **`narrationPreviewAudioURL` / `narrationPreviewIsFullLength`** still looked valid.
- **Change:** **`stopActiveVideoRender`** clears narration preview state when **`isPreparingVideoPreview`** (preview pipeline only—not final export), and marks pending preview/final changes.
- **Files:** `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Preview video: cap Edit Story TTS + progress (fix ~16% hang)

- **Cause:** **Preview** uses the same **`exportVideo`** path as final output, but **`RenderQuality.preview`** already caps **output** to **~20s** (`maximumDuration`). With **Edit Story** on, **`bypassNarrationPreviewAudio`** skips prepared preview M4A, so **`synthesizeNarrationIfNeeded`** ran **full-script** TTS (hundreds of utterances) while **`progressHandler`** stayed at **0.16** until done—looked frozen at ~16%.
- **Change:** For **preview** quality only, **`applyPreviewNarrationSynthesisBudget`** prefixes utterances using the same **estimated** seconds per segment as pacing (budget ≈ preview cap + 12s). Per-utterance **`Synthesizing narration i of n`** updates map to **0.16–0.23**; prepared-audio path reports **Using prepared narration audio.** at **0.22**.
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Pushed: `pro-version` @ `5ea3b4f`

- **Git:** `git push origin pro-version` — range `e87e975..5ea3b4f` (commit `5ea3b4f`).
- **Summary:** Edit Story toggle label + **Video Mode** locked to **Story** when Edit Story is on (`AppViewModel`, `ContentView`); user-visible export progress uses **Story** / **Slideshow** (`TimingMode`) instead of “real-life” copy (`VideoExporter`); `DESIGN_NOTES` + log entries above aligned.

### 2026-04-16 — Export status messages: Slideshow / Story (not “real-life”)

- **VideoExporter** user-visible `progressHandler` strings now use the same labels as **Video Mode** (**Story**, **Slideshow** from `TimingMode.rawValue`, not internal “real-life” wording). Updated: building composition, mixing music, export pass, caption-burn export.
- **Files:** `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Edit Story: rename toggle; lock Video Mode to Story

- **UI:** Edit tab toggle **Edit Media and Music** → **Edit Story**.
- **Behavior:** When **Edit Story** is on (`storyUsesBlockTimeline`), **Video Mode** is forced to **Story** and the Video tab picker only lists **Story**; **`selectedTimingMode`** is clamped to **`.story`** if anything tries to set another mode. Turning Edit Story off restores the full mode picker.
- **Files:** `CapcutApp/ContentView.swift`, `CapcutApp/AppViewModel.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Edit off final export: stop merging preview utterances (parity with Edit on)

- **Gap:** Edit on bypasses preview audio → **`VideoExporter`** synthesizes **every** `narrationSegmentsWholeScriptStyle` utterance. Edit off reused preview M4A built with **`mergedPreviewSegments`** (≤36) even for **`maximumDuration == nil`** (full-length export prep) → **fewer, longer** TTS chunks and different captions vs Edit on.
- **Change:** **`NarrationPreviewBuilder`** applies **`mergedPreviewSegments`** only when **`maximumDuration != nil`** (time-capped sample previews). Full-length preview keeps full utterance list. **`narrationPreviewSegmentationPolicy`** → **`full-length-preview-no-utterance-merge-v3`**.
- **Files:** `CapcutApp/NarrationPreviewBuilder.swift`, `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Story mode without Edit: same narration segmentation as Edit blocks

- **Intent:** Pre-Edit Story mode narration should match Edit: one shared rule (**`StoryScriptPartition.narrationSegmentsWholeScriptStyle`**) for a block’s text—whole script is treated as a single block when Edit is off.
- **Change:** **`NarrationPreviewBuilder`** (non-block) and **`VideoExporter.synthesizeNarrationIfNeeded`** (no `storyBlockNarrationSegments` / no forced paragraphs) call **`narrationSegmentsWholeScriptStyle(blockText: full script, …)`** instead of branching to long-form-only. **`narrationPreviewSegmentationPolicy`** bumped to **`whole-script-partition-v2`** so cached preview audio refreshes.
- **Files:** `CapcutApp/VideoExporter.swift`, `CapcutApp/NarrationPreviewBuilder.swift`, `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — CJK captions: less “busy” (revert paragraph flatten; wrap in one cue)

- **Issue:** Per-paragraph **`narrationSegmentsWholeScriptStyle`** flattening created **many more** TTS utterances → caption lines **changed too often** (“busy”).
- **Change:** Reverted that flattening. For **sentence-aligned** display, **`splitForCaptions`** lines joined with **`\n`** inside **one** **`CaptionSegment` / `SubtitleCue`** per utterance—fewer timed switches, readable multi-line block. (Whole-script TTS boundaries: see **“Story mode without Edit: same narration segmentation as Edit blocks”** above.)
- **Files:** `CapcutApp/StoryScriptPartition.swift`, `CapcutApp/VideoExporter.swift`, `CapcutApp/NarrationPreviewBuilder.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Caption sync only: restore `9859689` CJK layout (local; ship with next push)

- **User timeline:** **`9859689`** shipped without the later “long caption” problem; experiments after that (timing + alternate CJK chunking) caused regressions—not **`git reset`** failing.
- **This change:** Keep **`9859689`**-style CJK caption **construction** (**`sentenceAlignedTimedCaptionSegments`** + **`buildSentenceAlignedCues`**). Fix **playback lookup only:** **`SubtitleTimelineEngine.displayLeadSeconds = 0`**, **`time + displayLeadSeconds`** in **`AppViewModel.updateNarrationPreviewCaption`** and **`VideoExporter.captionText`** (**`CMTimeAdd`**, removed **`captionLagCompensation`** subtraction). No weighted / even intra-sentence cue splitting.
- **Files:** `CapcutApp/SubtitleTimelineEngine.swift`, `CapcutApp/VideoExporter.swift`, `CapcutApp/NarrationPreviewBuilder.swift`, `CapcutApp/AppViewModel.swift`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-16 — Pushed: `pro-version` @ `107f4aa`

- **Git**: `git push origin pro-version` — range `233ac27..107f4aa` (commit `107f4aa`).
- **Files in commit** `107f4aa`: `CapcutApp/ContentView.swift`, `CapcutApp/VideoExporter.swift`, `docs/GIT_PUSH_LOG.md` (caption slice fallback + script keyboard dismiss + log entries above).

### 2026-04-16 — Script: dismiss keyboard when tapping outside TextEditor

- **ContentView**: Tap header (brand/step strip) or the main **ScrollView** backdrop to clear `@FocusState` script focus; **Script** title + caption lines tappable to dismiss; `scrollDismissesKeyboard(.automatic)`; removed redundant `TextEditor` `.onTapGesture { isNarrationFocused = true }` that interfered with focus/scroll keyboard dismissal.

### 2026-04-16 — Long export: caption fallback when slice timing strips all text

- **VideoExporter** (`timedCaptionSegments`): If `makeCaptionSlices` returns no slices (every utterance normalizes to empty in `splitCaptionText`), use the same full-timeline fallback as when the timed loop yields no segments, instead of returning no caption segments. Prevents final renders with **Include captions** on but a completely uncaptioned file in that edge case.

### 2026-04-16 — Video tab: Story preflight, Stop, render session + docs

- **AppViewModel**: **`storyPoolTimelineExportBlockingReason`** (hybrid pool / **20s**-per-photo rule); **`activeVideoRenderSessionID`** so progress callbacks cannot overwrite status after **Stop**; **`stopActiveVideoRender()`**.
- **ContentView**: Orange **Add more media.** callout; red **Stop** on render progress card.
- **VideoExporter**: **`storyNeedsMoreMedia`** user text **Add more media.**
- **DESIGN_NOTES**: New section **Video tab: Story pool preflight, Stop, and status**.

### 2026-04-16 — Pushed: `pro-version` @ `e070c69`

- **Git**: `git push origin pro-version` — range `ef9184f..e070c69` (commit `e070c69`, 2026-04-16 07:57 −0700).
- **Files in commit** `e070c69`: `CapcutApp/AppViewModel.swift`, `CapcutApp/ContentView.swift`, `CapcutApp/VideoExporter.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-15 — Pushed: `pro-version` @ `59cf78b` (+ log @ `d81423a`)

- **Git**: `git push origin pro-version` — range `5ed61d2..59cf78b` (feature commit `59cf78b`, 2026-04-15 22:24 −0700); then `59cf78b..d81423a` (commit `d81423a`, push-log-only follow-up).
- **Edit Story**: Toggle **Edit Media and Music** on clears **`storyMusicBedSegments`** and **`storyEditBlocks`** (fully unassigned; no default Block 1); **`reconcileStoryEditBlocksWithScript()`** no longer seeds an empty block. **`validateMusicAssignmentSelection`** does not require media blocks first. **ContentView**: paragraph selection clear on enable; **Reset All** removed.
- **Files in feature commit** `59cf78b`: `CapcutApp/AppViewModel.swift`, `CapcutApp/ContentView.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-12 — Edit Story: toggle on = fully unassigned (no default Block 1)

- **AppViewModel**: **`resetStoryEditBlocksToDefault()`** clears **`storyMusicBedSegments`** and **`storyEditBlocks`** only (no implicit block covering the script). **`reconcileStoryEditBlocksWithScript()`** no longer seeds a block when empty.
- **ContentView**: Clearing paragraph selections when the toggle turns **on** (unchanged).
- **DESIGN_NOTES**: **Edit Media and Music: toggle and fresh state** updated.

### 2026-04-12 — Edit Story: music assign without media blocks

- **AppViewModel**: `validateMusicAssignmentSelection` no longer returns **Assign media in the Media tab first.** when `storyEditBlocks` is empty; paragraph music beds are independent of media block assignment (export still requires full media-block validation when you create video).
- **DESIGN_NOTES**: Edit tab bullet updated.

### 2026-04-15 — Edit Story: remove ambiguous Reset All

- **ContentView**: Removed **Reset All** under **Edit Media and Music** (behavior was easy to misunderstand: one block, all pool media, cleared music segments + selections). **`AppViewModel.resetStoryEditBlocksToDefault()`** remains for internal use when enabling **Edit Media and Music** (clears blocks + segment music).

### 2026-04-15 — Pushed: `pro-version` @ `8f7bc98`

- **Git**: `git push origin pro-version` — range `248f987..8f7bc98` (commit `8f7bc98`, 2026-04-15 14:35 −0700).
- **Script / Voice hide**: **`confirmationDialog`** (replaces legacy **`alert(item:)`**); **`minus.circle.fill`** row layout (**`HStack`**); **`.buttonStyle(.borderless)`** + **44×44** remove target inside voice **`ScrollView`**; removed blanket **`.disabled(availableVoices.isEmpty)`** on Language/Speed/Voice block; main **`ScrollView`** uses **`scrollDismissesKeyboard`** (keyboard dismiss without stealing control taps).
- **Files in that commit**: `CapcutApp/ContentView.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-15 — Script / Voice: fix Hide voice control (ScrollView + Menu)

- **ContentView**: Replaced **`Menu`** next to each voice row with a **`Button`** that sets **`voicePendingHide`** so the existing **Hide Voice?** alert runs. **`Menu`** popovers were mis-anchored inside the nested **ScrollView**, so “Hide Voice” appeared floating on the wrong row; the ellipsis is now a fixed hit target (`36×36`).
- **Follow-up**: Removed the Script card’s blanket **`.contentShape` + `.onTapGesture`** (dismiss keyboard)—it was stealing taps before they reached the ellipsis **`Button`**. Main studio **`ScrollView`** now uses **`.scrollDismissesKeyboard(.interactively)`** instead.
- **Later**: Removed trailing **⋯**; **−** in the **top-trailing** corner of each voice card → same **`voicePendingHide`** alert. Footer copy updated.
- **Voice hide UX**: Row is **`HStack`** (select | **`minus.circle.fill`**) so remove taps are not swallowed by the card **`Button`**; icon matches **Music → soundtrack queue** remove control.
- **Voice hide reliability**: **`confirmationDialog`** replaces **`alert(item:)` + legacy `Alert`**; **`.buttonStyle(.borderless)`** + **44×44** hit area on remove; removed blanket **`.disabled(availableVoices.isEmpty)`** on the Language/Speed/Voice group.

### 2026-04-15 — Edit Story: collapsible “How assigning works” + AppStorage

- **ContentView**: Edit → **Script paragraphs** (Media / Music): short always-on hint + **`DisclosureGroup`** for full copy; **`@AppStorage("fluxcut.editStoryHelpExpanded")`** persists expand/collapse (shared across Media | Music). Orange **`tint`** on the disclosure for consistency with FluxCut accents.

### 2026-04-15 — Export: Script speed applies to final TTS

- **VideoExporter**: **`exportVideo(..., speechRateMultiplier:)`** (default `1.0`); **`synthesizeNarrationIfNeeded`** passes it into **`SpeechVoiceLibrary.makeUtterance`** and scales **estimated** narration duration by **`effectiveSpeechRateMultiplier`** (measured utterances already reflect the rate).
- **AppViewModel**: Passes **`selectedNarrationSpeed`** into **`exportVideo`**.

### 2026-04-15 — Pushed: `pro-version` @ `180f298` (milestone)

- **Git**: `git push origin pro-version` — range `c1cd530..180f298` (commit `180f298`, 2026-04-15 09:57 −0700).
- **Edit Story UI**: Toggle label **Edit Media and Music**; **Reset All**; removed paragraph caption under toggle; music-assign empty-blocks message **Assign media in the Media tab first.**; **DESIGN_NOTES** aligned to the new toggle name.
- **Video strip thumbnails**: After picker file import completes, **`makeVideoThumbnail(for:)`** replaces the generic placeholder; **PhotoKit** prefetch retries with **network allowed** when the fast request returns nil; **`prefetchVideoThumbnailFromLibrary`** avoids `?? await` (Swift concurrency / build fix); pool/assign/media strip images use **`.id`** so SwiftUI refreshes when `previewImage` updates.
- **Same commit** as code: `CapcutApp/AppViewModel.swift`, `CapcutApp/ContentView.swift`, `docs/DESIGN_NOTES.md`, `docs/GIT_PUSH_LOG.md`.

### 2026-04-14 — Video pool thumbnails: file-import frame + PhotoKit retry

- **AppViewModel**: After a picker video finishes copying to disk (`completePickerVideoFileImport`), generate a **frame thumbnail** with `makeVideoThumbnail(for:)` and replace the generic placeholder so strip/assign thumbnails match the clip. **PhotoKit** prefetch retries with **network allowed** when the fast local request returns nil (e.g. iCloud-backed assets).
- **ContentView**: Pool/assign/media strip `Image(uiImage:)` views use a stable **`.id(item + preview object identity)`** so SwiftUI refreshes when `previewImage` updates from the shared placeholder to a real image.

### 2026-04-14 — Edit Story: Edit Media and Music toggle + Reset All

- **ContentView**: Toggle label **Edit Media and Music** (replaces **Use block timeline (Story mode)**); removed paragraph caption under the toggle; reset control labeled **Reset All** (same behavior: one block, clear paragraph selections).
- **AppViewModel**: Music-assign gate message when blocks are empty now says **Assign media in the Media tab first.** (no stale “turn on” wording).
- **DESIGN_NOTES**: User-facing toggle name updated to **Edit Media and Music**.

### 2026-04-14 — Docs: big-preview video autoplay spec

- **`docs/BIG_PREVIEW_VIDEO_AUTOPLAY_SPEC.md`**: Code design spec for muted looping preview (`LoopingVideoPlayerStore`, `AVPlayerLooper` vs template item readiness, slide lifecycle, UX contract, test checklist).
- **`docs/DESIGN_NOTES.md`**: New **Big-stage video preview** section with summary + link to spec; segment sheet bullet updated to point at spec.

### 2026-04-14 — `pro-version`: assign sheet controls, assigned-strip UX, preview autoplay, type-check split

- **ContentView**: Block **Assign** large preview uses **+** / **−** (add/remove current clip from draft) instead of an ellipsis menu. **Assigned** row: **video** badge on clips, **tap** selects that clip in the big preview, **double-tap** removes from draft (orange ring when that clip is the active slide). **LoopingVideoPlayerStore** calls `play()` when `AVPlayerItem` is **readyToPlay** if the preview slide is active (`setSlideActiveForPreview`), so muted looping preview auto-starts without relying on SwiftUI `onChange` for readiness. **storyBlockAssignSheet** split into `@ViewBuilder` helpers (`assignSheetDraftAssignedCell`, `assignSheetTabPage`, etc.) to fix **“unable to type-check in reasonable time”** build failures.
- **AppViewModel / VideoExporter / DESIGN_NOTES**: Carried with this push (Edit Story media vs music segments, per-segment beds export, earlier log bullets below).

### 2026-04-13 — Edit Story Media: remove duplicate Music queue card

- **ContentView**: Dropped the **Music queue** list from Edit → Media (same data as the Music tab; assign sheet still lists tracks). Short caption points users to Music for imports/order.
- **DESIGN_NOTES**: Media section description updated.

### 2026-04-13 — Edit Story: music spans independent of media blocks

- **Model**: `storyMusicBedSegments` is global; `StoryEditBlock` is media-only. Music assign validates paragraph bounds + block timeline, not media-block boundaries.
- **Export**: `makeStoryMusicBedSpansForExport()` + `exportVideo(..., storyMusicBedSpans:)`; `VideoExporter` maps spans to paragraph-timed beds.
- **UI / docs**: Music tab copy and `DESIGN_NOTES` updated.

### 2026-04-12 — Edit Story Music tab: duplicate script list + segment assign sheet

- **ContentView**: Music tab mirrors Media paragraph UI with separate selection; rows show **Segment** vs **Block**; **Assign** → full-screen segment soundtrack picker (exact block range required); **Clear music** clears all `soundtrackItemID`. **AppViewModel**: `clearAllStorySegmentSoundtracks()`.

### 2026-04-12 — Per-segment music: Edit Media|Music UI + export mix

- **VideoExporter**: `StoryBlockExportDescriptor.Block.segmentSoundtrackURL`; `buildStorySegmentMusicSlots` + `appendLoopedSourceAudio`; story block exports pass **per-segment** fills into `mergeAudioAndVideo` and `exportRealLifeComposition` (trim-aligned durations from trimmed narration, loop/trim per rules).
- **AppViewModel**: descriptor resolves `soundtrackItemID` → URL; **Assign media** preserves a single overlapping segment’s `soundtrackItemID` when re-saving the same range.
- **ContentView**: Edit Story **Media | Music** segmented control; Music tab = queue preview + per-segment menu picker (default = Music tab mix); assign sheet / labels use **segment** wording.
- **Docs**: `DESIGN_NOTES` export bullet updated to describe implemented mix.

### 2026-04-12 — Design: segments, media vs music, per-segment soundtrack rules

- **DESIGN_NOTES**: Document **segment** as the shared script unit; **Media** (visual) vs **Music** (sentiment) terminology; target **Edit** split into Media | Music; **one track per segment**; **always start at 0:00**; **trim** when narration is shorter than the file; **reuse** same file on another segment from 0:00 again; **loop** when narration is longer than the file. Clarify current export still uses global Music-tab mix; per-segment mix is future work.

### 2026-04-12 — Milestone push: `pro-version` @ `3381240`

Checkpoint pushed to `origin/pro-version` (Edit Story + Story mode block timeline milestone).

- **Export / sync**: Block-timeline story uses measured TTS sums only; `composeStoryBlockTimelineSegments` without estimated drift; preview renders up to **180s** for block mode; abort before export if block descriptor cannot build while toggle + validation imply blocks; legacy pool-wide story paths avoided when blocks compose.
- **Script**: Paragraph-aware **Clean Up** (blank-line boundaries for `StoryScriptPartition.nonEmptyParagraphs`); `reconcileStoryEditBlocksWithScript()` after cleanup; caption-off “20s per photo” planning warning skipped when **Use block timeline** is on.
- **Block assign sheet**: Shows **block** narration length estimate and character count (not whole script); **Block script** preview between thumbnail strip and Studio Tip; **Assigned** row reorders draft `mediaItemIDs` via drag-and-drop (same mechanism as Media tab), without changing global pool order.
- **Code touchpoints**: `VideoExporter`, `AppViewModel`, `ContentView`, `StoryScriptPartition`, `NarrationPreviewBuilder`; docs updated in this commit.

### 2026-04-12 — Edit Story preview duration + export guard

- **VideoExporter**: Edit Story block exports in **preview** quality cap at **180s** measured narration instead of **20s**, so block/photo sync is visible on long scripts.
- **AppViewModel**: if **Use block timeline** is on, Story mode, validation passes, but the block descriptor fails to build, abort before `exportVideo` with a message (removed mismatched `usesEditStoryBlockTimeline` flag that threw when the toggle was on but the descriptor was nil).

### 2026-04-12 — Edit Story: require block plan when toggle on

- (Superseded by guard above; removed `usesEditStoryBlockTimeline` / `storyBlockExportPlanMissing` from `VideoExporter`.)

### 2026-04-12 — Edit Story block A/V sync (measured narration only)

- `VideoExporter`: for block-timeline story export, narration timeline length and `composeStoryBlockTimelineSegments` use **measured** utterance sums only (no estimated padding / drift on last segment); **invalidStoryBlockPlan** if block mode would fall back to generic story timeline.

### 2026-04-12 — Edit Story tab and block export

- Added **Edit Story** studio step: media pool, music queue preview, script paragraphs with block badges, staged multi-clip assign to a contiguous paragraph range.
- Story mode export path: optional `paragraphNarrationSegments` + `StoryBlockExportDescriptor` in `VideoExporter`; paragraph-aligned synthesis and composed block timelines.
- Settings toggle **Show Edit Story tab** (`fluxcut.isEditStoryProEnabled`) as Pro placeholder.

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
- includes the caption-feature push and doc-only follow-ups through `fd98c80` (see numbered commits below)
- current branch tip may move later; use `git log origin/story_enhance -1 --oneline` for the latest commit on the remote branch

Commits for this checkpoint:

1. `e952d16` — `Caption look: Normal vs Stylish, two-pass CJK-friendly white fill`
2. `c6d609e` — `docs: record e952d16 in GIT_PUSH_LOG for caption look push`
3. `fd98c80` — `docs: expand GIT_PUSH_LOG for 2026-04-12 caption look checkpoint`

**`e952d16` — caption look (feature)**

- **`VideoExporter.CaptionStyle`** (`Normal` / `Stylish`) and **`AppViewModel.captionStyle`**; **Video** tab **Caption look** segmented control + Script **Current Caption** preview styling.
- **Normal:** semibold white on soft rounded pill (YouTube-like).
- **Stylish:** ~**1.5×** base size, **SF Rounded bold**, extra line spacing, **tight dim plate** (~40% black) for light backgrounds; **two-pass** outline then **pure white** fill (`drawCaption` + paired **`CATextLayer`** for burn-in) so CJK stays crisp white.
- **`docs/DESIGN_NOTES.md`:** new section **Caption look (Normal vs Stylish)**.

**`c6d609e`**

- **`GIT_PUSH_LOG.md`:** record primary hash `e952d16` for the caption look push.

**`fd98c80`**

- **`GIT_PUSH_LOG.md`:** expand the **2026-04-12** entry with numbered commits, remote range, and branch tip.

### 2026-04-12 (Script cleanup punctuation and ellipsis)

Pushed to the remote feature branch.

Details:

- branch: `story_enhance`
- remote: `origin` (`github.com:haobinzheng/video_studio_mini.git`)
- includes the script-cleanup fix and doc updates through the current checkpoint

Commits for this checkpoint:

1. `a298018` — `Fix script cleanup punctuation and ellipsis`
2. `c9892b1` — `Update git push log`

**`a298018` — script cleanup**

- Script `Clean Up` now treats dot-only lines such as `......`, `……`, and spaced dot runs as removable junk lines.
- Mid-sentence runs like `...`, `....`, `.....`, `…`, `……`, and mixed dot-like runs are normalized consistently so TTS does not read each period.
- Dot-run normalization now uses dot-equivalent weight instead of raw character count.
- Existing paragraph-ending punctuation is preserved without doubling, including cases with trailing spaces.
- Final-line missing punctuation detection is preserved, and repeated blank lines are removed for cleaner narration/caption timing.

**`c9892b1`**

- `GIT_PUSH_LOG.md`: record the script-cleanup checkpoint and its validated behavior.

### 2026-04-12 (caption display strip + narration preview synthesis guard)

Merged to **`main`** from **`story_enhance`** and **pushed** to `origin` (near-final product checkpoint).

Details:

- remote: `origin` (`github.com:haobinzheng/video_studio_mini.git`)
- default branch on remote: **`main`** (`origin/HEAD` → `origin/main`; there is no `master` branch in this repo)
- merge commit on `main`: **`c277617`** — `Merge branch 'story_enhance' into main (near-final narration/caption work)` — **2026-04-12 15:49:02 -0700**
- feature-branch tip that was merged (last feature commit before merge): **`cedda2a`** — `Fix caption trailing soft punctuation; bound narration preview TTS` — **2026-04-12 15:48:52 -0700**
- after a successful push, **`git rev-parse main`** and **`git rev-parse origin/main`** should both match **`c277617`** (until the next commit on `main`)

**Caption + preview (this checkpoint)**

- **`CaptionTextChunker.strippedCaptionForDisplay`:** strip only **soft** single-scalar tails (`, . ; : …` and CJK `，。；：、．` etc.); keep closing `)` `]` `}` `"` `?` `/` and similar; scalar-based matching for reliability (invisible/spaced-dot edge cases covered in earlier script-cleanup work).
- **`NarrationPreviewBuilder`:** **preview-only** cap on sequential `AVSpeechSynthesizer.write` passes by **merging** adjacent segments when over **36**; **90s** timeout per segment so a stuck synthesizer cannot hang the UI; **final video export** unchanged (no merge/timeout in `VideoExporter`).
- **`docs/DESIGN_NOTES.md`:** caption trim behavior + preview limits + default-branch / preview-vs-export notes documented alongside this push log update.
