# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

OverworkTracker is a macOS menu bar app (Swift 6, SwiftUI, SPM) that monitors foreground app usage and shows a humorous "verdict" about work intensity. It runs as a background service polling every 5 seconds.

## Build & Run

```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Run
swift run OverworkTracker
```

There are no tests, no linter, and no Makefile. VS Code launch configs exist for debug/release.

## Architecture

**Entry point:** `OverworkTrackerApp.swift` — `MenuBarExtra` wrapping `DashboardView`, fixed 320×460 window.

**Data flow:**

```
ActiveWindowTracker (5s timer)
  → DatabaseManager (SQLite via GRDB)
    → DashboardViewModel (10s refresh timer)
      → DashboardView (SwiftUI)
```

**Tracking loop** (`ActiveWindowTracker`):
- Every 5s: get frontmost app via `NSWorkspace`, optionally fetch window title via Accessibility API
- Check idle via `CGEventSource.secondsSinceLastEventType()` — if idle ≥300s, finalize session immediately
- On app change: insert new session; on same app: update `duration`/`endTime` in-place

**Persistence** (`DatabaseManager`): SQLite at `~/Library/Application Support/OverworkTracker/tracker.sqlite`. Two write paths: `insertSession()` (new session) and `updateSessionDuration()` (called every 5s on current session). Daily read aggregates via `SUM(duration)` grouped by `COALESCE(bundleID, appName)`.

**ViewModel** (`DashboardViewModel`): Lazy-initializes DB and tracker on first access. Refreshes UI every 10s (timer-based, not reactive).

## Key Design Decisions

- **Continuous writes over batching**: `endTime` and `duration` are updated every 5s tick — DB always reflects current state without recalculation at read time.
- **Idle ends sessions immediately**: When idle threshold is hit, the session finalizes at that moment, not when the user returns.
- **Accessibility is optional**: Window titles need Accessibility permission, but tracking works without it. `PermissionPromptView` prompts but doesn't block.
- **No reactive DB listening**: ViewModel polls on a timer; UI lags tracking by up to 10s by design.

## Data Model

`TrackingSession` is the only persisted type (GRDB `FetchableRecord`/`PersistableRecord`). Dates are stored as Doubles (Unix timestamps). Index on `startTime` for daily queries.

`AppUsageSummary` is a view-model-only struct with aggregated `totalDuration` and lazily fetched `NSImage` icon.

## VerdictBanner Tiers

`<1h` → `1-2h` → `2-4h` → `4-6h` → `6-8h` → `8-10h` → `10-12h` → `12h+`, color-coded green→blue→yellow→orange→red.
