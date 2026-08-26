# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-08-26

First release.

### Added

- **Pull gesture.** Press the menu bar icon and drag down to set a timer. A click-through
  overlay draws the line, a dashed rail showing how far the pull can reach, and tick marks
  at 5m, 15m, 30m, 1h, 2h and 4h. Drag back up into the menu bar to cancel.
- **Logarithmic scale.** Constant ratio per pixel across 1 minute to 4 hours, putting the
  halfway point of the screen at exactly 15 minutes. Rounding widens with length so long
  pulls do not shiver by single minutes. Linear mode is available in Settings.
- **Glass HUD.** Live duration, end time and preset band, following the cursor, clamped
  inside the screen's safe area so a notch never clips it.
- **Modifier keys.** `⌥` snaps to five minutes, `⇧` binds a Focus mode to the timer, `⌘`
  turns the pull into a wall-clock alarm.
- **Reminder card.** After releasing, a prompt asks what the timer is for. The text becomes
  the notification title. The timer runs regardless — the card is a label, not a gate.
- **`kurura` CLI.** Start, extend, pause, resume, cancel, status, stats and CSV export over
  a Unix domain socket, with `--json` for scripting. Installs to `PATH` without asking for
  an administrator password.
- **Automatic tagging** from the frontmost application, by bundle identifier.
- **Analytics window.** Twelve-week heatmap, breakdown by tag, today/week/streak/best-day
  figures and CSV export, backed by a local SQLite database.
- **Notifications** with Add 5 Minutes and Dismiss actions, a looping alarm option, custom
  alarm audio and optional ambience during a countdown.
- **Focus sync** through the Shortcuts CLI, and a Strict Focus mode that pushes blocked
  apps back down while a timer runs.
- **Shell hooks and webhooks** on start and finish, off by default.
- **Persistence.** Timers are stored as absolute end dates and restored across restarts;
  the engine recomputes against the wall clock on wake so a sleeping Mac cannot lose time.
  An idle-sleep assertion keeps the machine up while a timer runs.
- **Icon drawn in code.** `IconArtwork.swift` renders the iconset at build time and sheds
  detail below 64px, so the face never turns to mud at small sizes.

[0.1.0]: https://github.com/princechrix/kurura-isaha/releases/tag/v0.1.0
