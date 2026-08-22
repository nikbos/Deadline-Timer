# Deadline Timer

An Omarchy 4 bar widget that applies Parkinson's Law and The Deadline Effect to a Markdown schedule.
The status bar shows only the active task and its remaining time. The popup
contains the full timeline for the current day.

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/4111683a-2499-4d8c-91f2-4d5b0c9aec9b" />


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

The timeline reloads when the file changes. Top-priority checklist updates are
written back to the configured Markdown file.

## Controls

- Click the bar text to open or close the timeline.
- `h` / `l` or left/right arrows change day.
- `j` / `k` or up/down arrows select the previous/next event in the timeline (highlighted row).
- `t` returns to today.
- `r` reloads the Markdown file.
- `n` opens the new-task form and scrolls to it.
- `d` completes the top (first open) priority.
- `Enter` edits the selected event (falls back to the active slot if nothing is selected).
- `Escape` closes the popup.

The popup includes a **Top Priorities** checklist for the selected day. Press
`n` or click **+ New task** to add an untimed priority; click its checkbox when
complete. Priorities are stored beneath each `### Day:` heading in the Markdown
schedule. Every Sunday at 18:00, all top-priority checklists are cleared for the
new week.

Timed schedule items such as the midday checkpoint (`12:20-12:30`) and lunch
(`12:30-13:30`) belong in the Markdown schedule and appear in the normal
timeline.

### Creating Tasks

With the widget open, press `n` or click **+ New task**. Enter a priority name
and press Enter or click Save. Escape cancels the form.

New priorities are written to the selected day in the configured Markdown
schedule. Add timed schedule entries directly as Markdown table rows. Displayed
times follow the Omarchy clock format, including 12-hour and 24-hour formats.

### Editing Timeline Slots

Click a timeline row (or select it with `j`/`k` and press `Enter`) to edit its title and start/end times in the
popup form; Enter saves, Escape cancels; invalid times show an inline error;
blank end infers the next slot's start (or +30 minutes); a row's formatting
(bold, en-dash, 12h vs 24h) is preserved on save; equal start/end times mean
overnight-to-next-day.

The bar shows only the active task, for example:

```text
Deep Work #2  01:12:34
```

## License

MIT
