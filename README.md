# Deadline Timer

An Omarchy 4 bar widget that applies Parkinson's Law to a Markdown schedule.
The status bar shows only the active task and its remaining time. The popup
contains the full timeline for the current day.

## Install

```bash
omarchy plugin add https://github.com/nikbos/deadlineTimer --enable
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
- `n` opens the new-task form and scrolls to it.
- `Escape` closes the popup.

The widget also includes a daily midday checkpoint. By default, it occurs at
12:00 and reminds you to finish a rough outline or initial draft, review
progress, and plan the afternoon refinement phase. The checkpoint appears in
the popup and sends one desktop notification per day. Enable or disable it and
change its time through the widget settings.

### Creating Tasks

With the widget open, press `n` or click **+ New task**. Enter a task name,
start time, and end time. Press Enter in the task name field to move to the
start time, Enter in the start time field to move to the end time, and Enter in
the end time field to save the task. Escape cancels the form.

New tasks are written to the selected day in the configured Markdown schedule.
Displayed times and time-entry placeholders follow the Omarchy clock format,
including 12-hour and 24-hour formats.

The bar shows only the active task, for example:

```text
Deep Work #2  01:12:34
```

## License

MIT
