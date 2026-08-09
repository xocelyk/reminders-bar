# RemindersBar

A macOS menu bar app for Apple Reminders, organized the way a todo system
should be: **Todo** (scheduled, actionable), **Backlog** (someday), and
**Cycles** (recurring). Completed items disappear into Reminders' built-in
history.

Everything syncs through Apple Reminders (EventKit), so your phone, watch, and
Siri all stay in the loop.

## Features

- **One popover, one keystroke away** — click the menu bar icon, and the
  search field is already focused
- **Search or add** — typing filters your reminders; press ⏎ to add what you
  typed instead
- **Natural-language dates** — `submit invoices friday 10am`, `call mom
  tomorrow` (a time sets an alarm; a bare date is just a due date)
- **Recurrence** — `water plants every 3 days`, `gym every monday`, `review
  subscriptions monthly` → lands in Cycles with a real repeat rule; checking
  it off rolls it to the next occurrence
- **Smart routing** — dated → Todo, undated → Backlog, recurring → Cycles
- **Date-grouped view** — Overdue / Today / Tomorrow / Later, with Backlog
  collapsed at the bottom
- **Row actions** — click the circle to complete; hover for move/delete;
  right-click for move, rename, delete; double-click a title to rename inline
- Launch at login, no Dock icon, live sync when reminders change elsewhere

## Install

Requires macOS 14+ and Xcode Command Line Tools (no Xcode needed — builds
with plain `swiftc`, zero dependencies).

```sh
./build.sh --install
open /Applications/RemindersBar.app
```

macOS will ask for Reminders access on first launch.

The app expects lists named `Todo`, `Backlog`, and `Cycles`; it creates them
on demand as you add or move reminders. Your other lists still show up in the
date-grouped view — only `Backlog` is treated specially.

## Why lists instead of sections?

Reminders' in-list sections aren't exposed to third-party apps (EventKit has
no API for them), so top-level lists are the sturdiest structure that syncs
everywhere.

## License

MIT
