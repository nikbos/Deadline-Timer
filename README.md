# Deadline Timer

An Omarchy 4 bar widget that applies Parkinson's Law to a Markdown schedule.
The status bar shows only the active task and its remaining time. The popup
contains the full timeline for the current day.

## Install

```bash
omarchy plugin add <repository-url> --enable
omarchy restart shell
```

For local development:

```bash
mkdir -p ~/.config/omarchy/plugins/deadline-timer
cp manifest.json Panel.qml ScheduleModel.js README.md ~/.config/omarchy/plugins/deadline-timer/
omarchy plugin validate ~/.config/omarchy/plugins/deadline-timer
omarchy plugin enable deadline-timer
omarchy restart shell
```

## Schedule

The default schedule path is `~/.config/omarchy/schedule.md`. Configure another
path through the bar widget settings. The parser reads detailed sections in
the following format:

```markdown
### Monday: 

| Time | Activity |
|------|----------|
| **7:15-8:00 AM** | Deep Work #1 |
| **8:00-8:30 AM** | Breakfast |
```

The schedule is read-only and reloads when the file changes.

## Controls

- Click the bar text to open or close the timeline.
- `h` / `l` or left/right arrows change day.
- `j` / `k` or up/down arrows move through the timeline.
- `t` returns to today.
- `r` reloads the Markdown file.
- `Escape` closes the popup.

The bar shows only the active task, for example:

```text
Deep Work #2  01:12:34
```

## License

MIT
