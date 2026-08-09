# RemindersBar

macOS menu bar app for Apple Reminders. Reminders are organized into three
lists: `Todo` (has a due date), `Backlog` (no date), and `Cycles` (recurring).
Data lives in Apple Reminders via EventKit, so everything syncs with iOS,
Siri, etc.

## Usage

Click the menu bar icon to open a popover with a search field and your
incomplete reminders grouped by date (Overdue / Today / Tomorrow / Later).
Backlog is a collapsed section at the bottom.

Typing in the field filters reminders. Pressing ⏎ adds what you typed:

- `submit invoices friday 10am` — due Friday, with a 10am alarm → Todo
- `call mom tomorrow` — date-only due date → Todo
- `get a library card` — no date → Backlog
- `water plants every 3 days`, `gym every monday`, `rent monthly` —
  recurring → Cycles. Completing one advances it to the next occurrence.

Row actions: click the circle to complete, hover or right-click to move
between lists or delete, double-click a title (or right-click → Rename) to
rename.

The `Todo`/`Backlog`/`Cycles` lists are created on demand. Other lists still
appear in the date view; only `Backlog` is treated specially. In-list sections
would have been preferable to separate lists, but EventKit has no API for
them.

## Install

Needs macOS 14+ and the Xcode Command Line Tools (`swiftc`; no Xcode or
package manager involved).

```sh
./build.sh --install
open /Applications/RemindersBar.app
```

macOS asks for Reminders access on first launch. Note that rebuilding
re-signs the app ad hoc, which makes macOS ask again.

## License

MIT
