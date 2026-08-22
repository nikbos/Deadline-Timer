const { test } = require("node:test")
const assert = require("node:assert")

const ScheduleModel = require("../ScheduleModel.js")

const SAMPLE_SCHEDULE = [
  "### Monday:",
  "",
  "| Time | Activity |",
  "|------|----------|",
  "| **8:00-8:30 AM** | Breakfast |",
  "| **8:30-10:00 AM** | Deep Work #1 |",
  "| **10:00 AM** | Team meeting |",
  "| **11:00 PM - 1:00 AM** | Overnight Focus |",
  "",
  "### Tuesday:",
  "",
  "| Time | Activity |",
  "|------|----------|",
  "| **7:15-8:00 AM** | Deep Work #2 |",
  "| **6:30-7:30 PM** | Cardio |"
].join("\n")

function monday(hour, minute, second) {
  return new Date(2026, 7, 17, hour, minute, second || 0)
}

test("parseSchedule extracts slots with day, times and categories", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  assert.strictEqual(slots.length, 6)

  const breakfast = slots[0]
  assert.strictEqual(breakfast.day, 1)
  assert.strictEqual(breakfast.start, 480)
  assert.strictEqual(breakfast.end, 510)
  assert.strictEqual(breakfast.title, "Breakfast")
  assert.strictEqual(breakfast.category, "meal")

  const standup = slots[2]
  assert.strictEqual(standup.title, "Team meeting")
  assert.strictEqual(standup.category, "admin")
  assert.strictEqual(standup.start, 600)
  assert.strictEqual(standup.end, 1380)

  const workout = slots[5]
  assert.strictEqual(workout.category, "movement")
})

test("parseSchedule handles a single-time slot using the next slot as its end", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  assert.strictEqual(slots[2].end, slots[3].start)
})

test("parseSchedule parses overnight ranges into an end beyond 1440", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  const overnight = slots[3]
  assert.strictEqual(overnight.title, "Overnight Focus")
  assert.strictEqual(overnight.start, 1380)
  assert.strictEqual(overnight.end, 1500)
})

test("parseSchedule ignores header and separator rows", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  assert.ok(slots.every((slot) => slot.title !== "Time" && !/^-+$/.test(slot.title)))
})

test("parseSchedule infers a 30-minute duration for a trailing single time", () => {
  const raw = "### Saturday:\n\n| Time | Activity |\n|------|----------|\n| **9:00 PM** | Wind down |\n"
  const slots = ScheduleModel.parseSchedule(raw)
  assert.strictEqual(slots.length, 1)
  assert.strictEqual(slots[0].start, 1260)
  assert.strictEqual(slots[0].end, 1290)
  assert.strictEqual(slots[0].category, "rest")
})

test("parseSchedule supports en-dash separators and 24-hour times", () => {
  const raw = "### Wednesday:\n\n| Time | Activity |\n|------|----------|\n| **14:00–14:30** | Coding |\n"
  const slots = ScheduleModel.parseSchedule(raw)
  assert.strictEqual(slots.length, 1)
  assert.strictEqual(slots[0].start, 840)
  assert.strictEqual(slots[0].end, 870)
})

test("topPriorities reads checklist items for a given day", () => {
  const raw = [
    "### Monday:",
    "- [ ] Finish report",
    "- [x] Send email",
    "- [X] Book room",
    "",
    "### Tuesday:",
    "- [ ] Plan sprint"
  ].join("\n")
  const priorities = ScheduleModel.topPriorities(raw, 1)
  assert.strictEqual(priorities.length, 3)
  assert.deepStrictEqual(priorities[0], { title: "Finish report", done: false })
  assert.strictEqual(priorities[1].done, true)
  assert.strictEqual(priorities[2].done, true)
  assert.strictEqual(ScheduleModel.topPriorities(raw, 2).length, 1)
  assert.strictEqual(ScheduleModel.topPriorities(raw, 3).length, 0)
})

test("currentSlot returns the matching slot with remaining time and progress", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  const active = ScheduleModel.currentSlot(slots, monday(8, 15))
  assert.ok(active)
  assert.strictEqual(active.title, "Breakfast")
  assert.strictEqual(active.remainingSeconds, 900)
  assert.strictEqual(active.durationSeconds, 1800)
  assert.strictEqual(active.progress, 0.5)
})

test("currentSlot returns null between slots", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  const tuesday = new Date(2026, 7, 18, 10, 0)
  assert.strictEqual(tuesday.getDay(), 2)
  assert.strictEqual(ScheduleModel.currentSlot(slots, tuesday), null)
})

test("currentSlot matches a mid-day slot", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  const active = ScheduleModel.currentSlot(slots, new Date(2026, 7, 18, 19, 0))
  assert.ok(active)
  assert.strictEqual(active.title, "Cardio")
})

test("currentSlot keeps an overnight slot active into the next day", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  const tuesday = new Date(2026, 7, 18, 0, 30)
  assert.strictEqual(tuesday.getDay(), 2)
  const active = ScheduleModel.currentSlot(slots, tuesday)
  assert.ok(active)
  assert.strictEqual(active.title, "Overnight Focus")
  assert.strictEqual(active.remainingSeconds, 1800)
})

test("currentSlot reports full remaining time for a multi-day overnight span", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  const active = ScheduleModel.currentSlot(slots, monday(23, 30))
  assert.ok(active)
  assert.strictEqual(active.title, "Overnight Focus")
  assert.strictEqual(active.remainingSeconds, 5400)
})

test("formatMinutes supports 12-hour and 24-hour clocks", () => {
  assert.strictEqual(ScheduleModel.formatMinutes(480, false), "8:00 AM")
  assert.strictEqual(ScheduleModel.formatMinutes(780, false), "1:00 PM")
  assert.strictEqual(ScheduleModel.formatMinutes(0, false), "12:00 AM")
  assert.strictEqual(ScheduleModel.formatMinutes(480, true), "08:00")
  assert.strictEqual(ScheduleModel.formatMinutes(1439, true), "23:59")
})

test("formatRemaining formats hours, minutes and seconds", () => {
  assert.strictEqual(ScheduleModel.formatRemaining(0), "00:00")
  assert.strictEqual(ScheduleModel.formatRemaining(59), "00:59")
  assert.strictEqual(ScheduleModel.formatRemaining(60), "01:00")
  assert.strictEqual(ScheduleModel.formatRemaining(3661), "01:01:01")
})

test("dayName returns capitalized day names", () => {
  assert.strictEqual(ScheduleModel.dayName(0), "SUNDAY")
  assert.strictEqual(ScheduleModel.dayName(6), "SATURDAY")
  assert.strictEqual(ScheduleModel.dayName(-1), "SATURDAY")
})

test("dayIndex maps day names and prefixes and rejects unknown names", () => {
  assert.strictEqual(ScheduleModel.dayIndex("Monday"), 1)
  assert.strictEqual(ScheduleModel.dayIndex("monday"), 1)
  assert.strictEqual(ScheduleModel.dayIndex("monday night"), 1)
  assert.strictEqual(ScheduleModel.dayIndex("Mond"), -1)
  assert.strictEqual(ScheduleModel.dayIndex("sat"), -1)
  assert.strictEqual(ScheduleModel.dayIndex("Holiday"), -1)
})

test("dayProgress tracks the fraction of the day elapsed", () => {
  assert.strictEqual(ScheduleModel.dayProgress(monday(0, 0)), 0)
  assert.strictEqual(ScheduleModel.dayProgress(monday(12, 0)), 0.5)
  assert.ok(Math.abs(ScheduleModel.dayProgress(monday(23, 59, 59)) - 86399 / 86400) < 1e-9)
})

test("slotsForDay filters slots by day", () => {
  const slots = ScheduleModel.parseSchedule(SAMPLE_SCHEDULE)
  assert.strictEqual(ScheduleModel.slotsForDay(slots, 1).length, 4)
  assert.strictEqual(ScheduleModel.slotsForDay(slots, 2).length, 2)
  assert.strictEqual(ScheduleModel.slotsForDay(slots, 0).length, 0)
})

test("parseTime parses single clock values into minutes of day", () => {
  assert.strictEqual(ScheduleModel.parseTime("8:30 AM"), 510)
  assert.strictEqual(ScheduleModel.parseTime("14:00"), 840)
  assert.strictEqual(ScheduleModel.parseTime("8:00"), 480)
  assert.strictEqual(ScheduleModel.parseTime("12:00 AM"), 0)
  assert.strictEqual(ScheduleModel.parseTime("12:30 PM"), 750)
  assert.strictEqual(ScheduleModel.parseTime("8:15pm"), 1215)
  assert.strictEqual(ScheduleModel.parseTime(""), null)
  assert.strictEqual(ScheduleModel.parseTime("8:60"), null)
  assert.strictEqual(ScheduleModel.parseTime("25:00"), null)
  assert.strictEqual(ScheduleModel.parseTime("noon"), null)
})

test("resolveEnd infers 30 minutes, rolls overnight and rejects garbage", () => {
  assert.strictEqual(ScheduleModel.resolveEnd(480, "8:30 AM"), 510)
  assert.strictEqual(ScheduleModel.resolveEnd(480, "8:30"), 510)
  assert.strictEqual(ScheduleModel.resolveEnd(480, ""), 510)
  assert.strictEqual(ScheduleModel.resolveEnd(1380, "1:00 AM"), 1500)
  assert.strictEqual(ScheduleModel.resolveEnd(1380, "1:00"), 1500)
  assert.strictEqual(ScheduleModel.resolveEnd(480, "garbage"), null)
})

test("updateSlot rewrites a slot row and round-trips through parseSchedule", () => {
  const updated = ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 0, 570, 600, "Brunch")
  assert.ok(updated.split("\n").includes("| **9:30-10:00 AM** | Brunch |"))
  const breakfast = ScheduleModel.parseSchedule(updated)[0]
  assert.strictEqual(breakfast.start, 570)
  assert.strictEqual(breakfast.end, 600)
  assert.strictEqual(breakfast.title, "Brunch")
})

test("updateSlot preserves en-dash and 24-hour formatting", () => {
  const raw = "### Wednesday:\n\n| Time | Activity |\n|------|----------|\n| **14:00–14:30** | Coding |\n"
  const updated = ScheduleModel.updateSlot(raw, 3, 0, 900, 930, "Deep Work")
  assert.ok(updated.split("\n").includes("| **15:00–15:30** | Deep Work |"))
})

test("updateSlot renders an explicit 12-hour overnight range", () => {
  const updated = ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 3, 1320, 1500, "Night Shift")
  assert.ok(updated.split("\n").includes("| **10:00 PM - 1:00 AM** | Night Shift |"))
  const slots = ScheduleModel.parseSchedule(updated)
  assert.strictEqual(slots[3].start, 1320)
  assert.strictEqual(slots[3].end, 1500)
})

test("updateSlot keeps a single-time row single when the end is unchanged", () => {
  const updated = ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 2, 600, 1380, "Team sync")
  assert.ok(updated.split("\n").includes("| **10:00 AM** | Team sync |"))
})

test("updateSlot expands a single-time row into a range when the end changes", () => {
  const updated = ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 2, 600, 660, "Team sync")
  assert.ok(updated.includes("**10:00-11:00 AM**"))
})

test("updateSlot sanitizes pipes and newlines out of titles", () => {
  const updated = ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 0, 480, 510, "Sync | task\nnext")
  const editedLine = updated.split("\n").find((line) => line.includes("Sync"))
  assert.ok(editedLine)
  assert.strictEqual(editedLine.split("|").length, 4)
  const slots = ScheduleModel.parseSchedule(updated)
  assert.strictEqual(slots[0].title, "Sync task next")
})

test("updateSlot returns null for unknown days and out-of-range rows", () => {
  assert.strictEqual(ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 0, 0, 480, 510, "Nope"), null)
  assert.strictEqual(ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 99, 480, 510, "Nope"), null)
})

test("updateSlot leaves other days unchanged", () => {
  const updated = ScheduleModel.updateSlot(SAMPLE_SCHEDULE, 1, 0, 570, 600, "Brunch")
  const lines = updated.split("\n")
  assert.ok(lines.includes("| **7:15-8:00 AM** | Deep Work #2 |"))
  assert.ok(lines.includes("| **6:30-7:30 PM** | Cardio |"))
})