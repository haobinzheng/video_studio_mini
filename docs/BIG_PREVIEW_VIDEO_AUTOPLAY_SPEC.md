# Big-stage muted video preview — code design spec

**Status:** Implemented (FluxCut / CapcutApp)  
**Primary code:** `CapcutApp/ContentView.swift` — `ProjectVideoStageView`, `LoopingVideoPreview`, `LoopingVideoPlayerStore`  
**Canonical product notes:** `docs/DESIGN_NOTES.md` (section *Big-stage video preview*)

---

## 1. Purpose and scope

The **large carousel preview** for pool videos must:

- **Autoplay** when the clip is able to play and the slide is **active**, without requiring a tap.
- Offer **optional manual Play** while the asset is still **buffering / not yet “ready”** (early start).
- Stay **muted** (studio preview, not user-initiated sound).
- **Loop** seamlessly for inspection (implementation uses `AVPlayerLooper`).
- Work for **resolved file URLs** (embedded file on `MediaItem`, or async PhotoKit / import resolution via `ProjectVideoStageView`).

Surfaces:

- **Edit → Media** tab (`mediaStage` → `ProjectVideoStageView`).
- **Edit Story → block Assign** full-screen sheet (same `mediaStage` / `ProjectVideoStageView`).

Non-goals for this spec: export pipeline, full-screen export player, AirPlay picker behavior.

---

## 2. UX contract (authoritative)

| Phase | What the user sees | What happens |
|--------|-------------------|--------------|
| Slide active, asset loading | Placeholder image + spinner; optional **Play** button (unless user already chose early play and only spinner remains). | Store may call `play()` on the queue player even before “ready” so AVFoundation can start as soon as possible. |
| Optional early play | User taps **Play** during load. | `userChoseEarlyPlay = true` (view state); `player.play()`; video layer can show before readiness flags flip. |
| Ready | Spinner and **Play** control **hide** (`isReadyForPlayback` true). | Autoplay path ensures `play()`; redundant `play()` is safe. |
| Slide inactive | Preview paused and seeked to start. | `pauseAndReset()`; optional early-play hint reset where applicable. |

Users **never** need to avoid manual Play for autoplay to work later; manual Play is **additive**, not mutually exclusive with autoplay.

---

## 3. Architecture (types)

```
ProjectVideoStageView
  ├─ Resolves playback URL (embeddedVideoFileURL or async resolveVideoPreviewPlaybackURL)
  └─ LoopingVideoPreview(url:placeholder:isActive:)
        @StateObject LoopingVideoPlayerStore(url:)
```

- **`ProjectVideoStageView`**: Bridges `AppViewModel` / PhotoKit to a stable `URL`, then shows `LoopingVideoPreview`. Uses `.id(url.absoluteString)` so a **new** URL recreates preview state.
- **`LoopingVideoPreview`**: SwiftUI shell — placeholder, `VideoPlayer`, loading / error overlays, optional Play button. Forwards **slide visibility** to the store via `setSlideActiveForPreview(_:)` on `onAppear`, `onChange(of: isActive)`, `onDisappear`.
- **`LoopingVideoPlayerStore`**: `ObservableObject` owning `AVQueuePlayer`, `AVPlayerLooper`, readiness/failure published state, and all **playback / readiness** logic.

**Why not rely on SwiftUI `onChange(of: isReadyForPlayback)` alone?**  
Published updates on nested observation can be **missed** or ordered badly vs. view lifetime. Readiness-driven `play()` is implemented **inside the store** on the same main-queue path as AVFoundation callbacks, and slide activation always requests `play()` explicitly (see §5–6).

---

## 4. AVFoundation model

- **`AVQueuePlayer`**: `isMuted = true`, `actionAtItemEnd = .none` (looper manages repeats).
- **`AVPlayerLooper(player:templateItem:)`**: Uses the **template** `AVPlayerItem` to build **replica** items for looping. The item the user creates in `init` is **not** guaranteed to be the one whose `status` best reflects “you can show looping video.”
- **`AVPlayerLooper.status`** (KVO): `.unknown` → `.ready` / `.failed` / `.cancelled`. **`.ready`** means the looper can perform looping playback — this is a **primary** readiness signal for autoplay.
- **Template `AVPlayerItem.status`**: Still observed for **`.readyToPlay`** and **`.failed`** as a **secondary** signal and for consistency with asset-level failures.

Apple’s sample flow for a looper: construct looper, then call **`[player play]`**. We align with that by **always** calling `player.play()` when the preview slide becomes **active**, not only after a single KVO path fires.

---

## 5. Readiness and failure (`LoopingVideoPlayerStore`)

### 5.1 Published UI state

- **`isReadyForPlayback`**: `true` when `looper.status == .ready` **or** `templateItem.status == .readyToPlay`.
- **`loadDidFail`**: `true` when **either** `looper.status == .failed` **or** `templateItem.status == .failed`.

### 5.2 Observers

- `templateItem.publisher(for: \.status)` → `receive(on: DispatchQueue.main)` → `refreshReadinessAndMaybePlay()`.
- `looper.publisher(for: \.status)` → same.

### 5.3 `refreshReadinessAndMaybePlay()`

1. If either side reports **failed** → set `loadDidFail`, clear ready flag, return.
2. Else if looper **ready** or item **readyToPlay** → set `isReadyForPlayback`, clear failure; if **`isSlideActiveForPreview`** → `play()`.

### 5.4 Initial sync

After wiring observers, **`DispatchQueue.main.async { refreshReadinessAndMaybePlay() }`** catches states that were already terminal before subscription (avoids “never fires” edge cases).

---

## 6. Slide lifecycle (`isSlideActiveForPreview`)

- **`setSlideActiveForPreview(true)`**  
  - Sets `isSlideActiveForPreview = true`.  
  - Calls `refreshReadinessAndMaybePlay()`.  
  - Calls **`player.play()` unconditionally** so playback is requested **before** readiness if needed (matches manual Play and Apple’s looper usage).

- **`setSlideActiveForPreview(false)`**  
  - `pauseAndReset()` (pause + seek to zero).

`LoopingVideoPreview` must call this whenever the **TabView** (or equivalent) selection implies this page is the **visible** big preview, so off-screen pages do not keep playing.

---

## 7. Manual Play button (view-only)

- Shown only when `isActive && !isReadyForPlayback && !loadDidFail` (and not hidden by `userChoseEarlyPlay` policy for the button itself).
- Action: `userChoseEarlyPlay = true`, `store.play()`.
- Does **not** gate autoplay when ready; store still runs `play()` on readiness if the slide is active.

---

## 8. File and symbol index

| Symbol | Role |
|--------|------|
| `ProjectVideoStageView` | URL resolution + `LoopingVideoPreview` host |
| `LoopingVideoPreview` | UI + lifecycle → `setSlideActiveForPreview` |
| `LoopingVideoPlayerStore` | Player, looper, KVO, `play` / `pauseAndReset` |
| `mediaStage(for:isActive:)` | Chooses image vs `ProjectVideoStageView` |

---

## 9. Testing checklist (manual)

- Import video → land on big preview **without** tapping Play → video starts shortly after load; Play overlay disappears when ready.
- Tap Play **during** buffer → early motion possible; when ready, overlay still dismisses; playback continues.
- Swipe to another clip and back → preview pauses off-screen and resumes logic for active slide.
- Assign sheet: same behavior for resolved URLs.

---

## 10. Future considerations

- If preview ever uses **non-looper** playback, revisit dual signals (looper vs item) — may collapse to item-only.
- If TabView preloading changes, re-validate `onAppear` / `onDisappear` / `isActive` wiring for false `play()` calls on background pages.
- Optional: surface `looper.error` / `item.error` in UI for debugging failed state.

---

*Last updated: 2026-04-14 (spec authored for repo documentation).*
