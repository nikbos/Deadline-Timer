var DAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

function clean(value) {
  return String(value || "")
    .replace(/<[^>]+>/g, "")
    .replace(/\*\*/g, "")
    .replace(/`/g, "")
    .replace(/\s+/g, " ")
    .trim()
}

function dayIndex(name) {
  var normalized = String(name || "").toLowerCase()
  for (var i = 0; i < DAY_NAMES.length; i++) {
    if (normalized === DAY_NAMES[i] || normalized.indexOf(DAY_NAMES[i]) === 0) return i
  }
  return -1
}

function parseClock(value, suffix) {
  var match = String(value || "").trim().match(/^(\d{1,2})(?::(\d{2}))?$/)
  if (!match) return null

  var hour = Number(match[1])
  var minute = Number(match[2] || 0)
  var meridiem = String(suffix || "").toUpperCase()
  if (minute > 59) return null

  if (meridiem === "AM") hour = hour === 12 ? 0 : hour
  if (meridiem === "PM") hour = hour === 12 ? 12 : hour + 12
  if (hour > 23) return null
  return hour * 60 + minute
}

function parseTimeRange(value) {
  var text = clean(value).replace(/[–—]/g, "-")
  var match = text.match(/^(\d{1,2}(?::\d{2})?)\s*(AM|PM)?\s*-\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM)?$/i)
  if (match) {
    var sharedSuffix = match[4] || match[2]
    var startSuffix = match[2] || sharedSuffix
    if (!match[2] && match[4]) {
      var startHour = Number(match[1].split(":")[0])
      var endHour = Number(match[3].split(":")[0])
      if (startHour !== 12 && (startHour > endHour || endHour === 12))
        startSuffix = match[4] === "PM" ? "AM" : "PM"
    }
    var start = parseClock(match[1], startSuffix)
    var end = parseClock(match[3], match[4] || sharedSuffix)
    if (start !== null && end !== null) {
      if (end <= start && (match[4] || match[2])) end += 1440
      return { start: start, end: end }
    }
  }

  var single = text.match(/^(\d{1,2}(?::\d{2})?)\s*(AM|PM)?$/i)
  if (!single) return null
  var singleStart = parseClock(single[1], single[2])
  return singleStart === null ? null : { start: singleStart, end: null }
}

function categoryFor(title) {
  var text = String(title || "").toLowerCase()
  if (/deep work|creative|research|coding|implementation|execution|analysis/.test(text)) return "deep-work"
  if (/training|cardio|strength|yoga|stretch|walk/.test(text)) return "movement"
  if (/breakfast|lunch|dinner|meal|eat/.test(text)) return "meal"
  if (/sleep|wake up|wind down|evening routine/.test(text)) return "rest"
  if (/reading|learning|study/.test(text)) return "learning"
  if (/cleaning|chores|errands|gardening/.test(text)) return "life"
  if (/meeting|collaboration|email|admin/.test(text)) return "admin"
  return "other"
}

function parseSchedule(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var result = []
  var currentDay = -1
  var ordinal = 0

  for (var i = 0; i < lines.length; i++) {
    var heading = lines[i].match(/^###\s+([^:]+):/)
    if (heading) {
      currentDay = dayIndex(clean(heading[1]))
      continue
    }
    if (currentDay < 0 || lines[i].indexOf("|") !== 0) continue

    var cells = lines[i].split("|")
    if (cells.length < 3) continue
    var time = parseTimeRange(cells[1])
    var title = clean(cells[2])
    if (!time || !title || /^time$/i.test(title) || /^-+$/.test(title)) continue
    result.push({
      id: currentDay + "-" + ordinal++,
      day: currentDay,
      start: time.start,
      end: time.end,
      title: title,
      category: categoryFor(title)
    })
  }

  for (var j = 0; j < result.length; j++) {
    if (result[j].end === null) {
      var next = null
      for (var k = j + 1; k < result.length; k++) {
        if (result[k].day === result[j].day) {
          next = result[k]
          break
        }
      }
      result[j].end = next ? next.start : result[j].start + 30
    }
    if (result[j].end <= result[j].start) result[j].end = result[j].start + 30
  }
  return result
}

function slotsForDay(schedule, day) {
  return (schedule || []).filter(function(slot) { return slot.day === day })
}

function topPriorities(raw, day) {
  var lines = String(raw || "").split(/\r?\n/)
  var result = []
  var currentDay = -1

  for (var i = 0; i < lines.length; i++) {
    var heading = lines[i].match(/^###\s+([^:]+):/)
    if (heading) {
      currentDay = dayIndex(clean(heading[1]))
      continue
    }
    if (currentDay !== day) continue

    var match = lines[i].match(/^\s*-\s+\[([ xX])\]\s+(.+?)\s*$/)
    if (match) result.push({ title: clean(match[2]), done: match[1].toLowerCase() === "x" })
  }
  return result
}

function currentSlot(schedule, date) {
  var now = date || new Date()
  var minute = now.getHours() * 60 + now.getMinutes() + now.getSeconds() / 60
  var today = now.getDay()
  var candidates = slotsForDay(schedule, today)
  var yesterday = (today + 6) % 7
  var previous = slotsForDay(schedule, yesterday)
  for (var p = 0; p < previous.length; p++) {
    if (previous[p].end > 1440) {
      candidates.push({
        id: previous[p].id,
        day: previous[p].day,
        start: previous[p].start - 1440,
        end: previous[p].end - 1440,
        title: previous[p].title,
        category: previous[p].category
      })
    }
  }
  for (var i = 0; i < candidates.length; i++) {
    if (minute >= candidates[i].start && minute < candidates[i].end) {
      var remaining = Math.max(0, Math.ceil((candidates[i].end - minute) * 60))
      return {
        id: candidates[i].id,
        title: candidates[i].title,
        category: candidates[i].category,
        start: candidates[i].start,
        end: candidates[i].end,
        remainingSeconds: remaining,
        durationSeconds: Math.max(1, (candidates[i].end - candidates[i].start) * 60),
        progress: Math.max(0, Math.min(1, (minute - candidates[i].start) / (candidates[i].end - candidates[i].start)))
      }
    }
  }
  return null
}

function dayProgress(date) {
  var now = date || new Date()
  var seconds = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
  return Math.max(0, Math.min(1, seconds / 86400))
}

function formatMinutes(minutes, use24HourClock) {
  var normalized = ((Number(minutes) % 1440) + 1440) % 1440
  var hour = Math.floor(normalized / 60)
  var minute = normalized % 60
  if (use24HourClock) {
    return (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute
  }
  var suffix = hour >= 12 ? "PM" : "AM"
  var displayHour = hour % 12 || 12
  return displayHour + ":" + (minute < 10 ? "0" : "") + minute + " " + suffix
}

function formatRemaining(seconds) {
  var value = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(value / 3600)
  var minutes = Math.floor((value % 3600) / 60)
  var secs = value % 60
  function pad(number) { return number < 10 ? "0" + number : String(number) }
  return (hours > 0 ? pad(hours) + ":" : "") + pad(minutes) + ":" + pad(secs)
}

function dayName(day) {
  var index = ((Number(day) % 7) + 7) % 7
  return DAY_NAMES[index].toUpperCase()
}

function parseTime(text) {
  var match = String(text || "").trim().match(/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$/i)
  if (!match) return null

  var hour = Number(match[1])
  var minute = Number(match[2] || 0)
  if (minute > 59 || hour > 23) return null

  var meridiem = String(match[3] || "").toUpperCase()
  if (meridiem === "AM") hour = hour === 12 ? 0 : hour
  if (meridiem === "PM") hour = hour === 12 ? 12 : hour + 12
  return hour * 60 + minute
}

function resolveEnd(start, endText) {
  var text = String(endText || "").trim()
  if (!text) return start + 30
  var end = parseTime(text)
  if (end === null) return null
  if (end <= start) end += 1440
  return end
}

function updateSlot(raw, day, rowIndex, newStart, newEnd, newTitle) {
  var lines = String(raw || "").split(/\r?\n/)
  var currentDay = -1
  var slots = []

  for (var i = 0; i < lines.length; i++) {
    var heading = lines[i].match(/^###\s+([^:]+):/)
    if (heading) {
      currentDay = dayIndex(clean(heading[1]))
      continue
    }
    if (currentDay !== day || lines[i].indexOf("|") !== 0) continue

    var cells = lines[i].split("|")
    if (cells.length < 3) continue
    var parsed = parseTimeRange(cells[1])
    var title = clean(cells[2])
    if (!parsed || !title || /^time$/i.test(title) || /^-+$/.test(title)) continue

    var plainTime = cells[1].replace(/\*\*/g, "")
    slots.push({
      lineIndex: i,
      cells: cells,
      start: parsed.start,
      end: parsed.end,
      isSingle: plainTime.indexOf("-") < 0
        && plainTime.indexOf("–") < 0
        && plainTime.indexOf("—") < 0
    })
  }

  if (rowIndex < 0 || rowIndex >= slots.length) return null

  var slot = slots[rowIndex]

  function fmt24(minutes) { return formatMinutes(minutes, true) }
  function fmt12(minutes) { return formatMinutes(minutes, false) }
  function fmt12ns(minutes) {
    var normalized = ((Number(minutes) % 1440) + 1440) % 1440
    var hour = Math.floor(normalized / 60) % 12 || 12
    var minute = normalized % 60
    return hour + ":" + (minute < 10 ? "0" : "") + minute
  }
  function meridiem(minutes) {
    return Math.floor(((Number(minutes) % 1440) + 1440) % 1440 / 60) >= 12 ? "PM" : "AM"
  }

  var plainTime = slot.cells[1].replace(/\*\*/g, "")
  var wasBold = slot.cells[1].indexOf("**") >= 0
  var sepChar = "-"
  if (plainTime.indexOf("–") >= 0) sepChar = "–"
  else if (plainTime.indexOf("—") >= 0) sepChar = "—"
  var meridiemMatches = plainTime.match(/(AM|PM)/gi) || []
  var countMeridiem = meridiemMatches.length
  var use24 = countMeridiem === 0
  var wasExplicit = countMeridiem === 2
  var isOvernight = newEnd > 1440

  function renderRange() {
    if (use24 && !isOvernight) return fmt24(newStart) + sepChar + fmt24(newEnd)
    if (use24 && isOvernight) return fmt12(newStart) + " - " + fmt12(newEnd)
    if (wasExplicit) return fmt12(newStart) + " " + sepChar + " " + fmt12(newEnd)
    if (meridiem(newStart) === meridiem(newEnd) && !isOvernight)
      return fmt12ns(newStart) + sepChar + fmt12ns(newEnd) + " " + meridiem(newStart)
    return fmt12(newStart) + " " + sepChar + " " + fmt12(newEnd)
  }

  var timeText
  if (slot.isSingle) {
    var inferredEnd = newStart + 30
    for (var n = rowIndex + 1; n < slots.length; n++) {
      inferredEnd = slots[n].start
      break
    }
    if (newEnd === inferredEnd) {
      timeText = use24 ? fmt24(newStart) : fmt12(newStart)
    } else {
      timeText = renderRange()
    }
  } else {
    timeText = renderRange()
  }

  if (wasBold) timeText = "**" + timeText + "**"

  var titleText = String(newTitle || "").replace(/[|\r\n]/g, " ").trim()
  if (slot.cells[2].indexOf("**") >= 0) titleText = "**" + titleText + "**"

  lines[slot.lineIndex] = "| " + timeText + " | " + titleText + " |"
  return lines.join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    dayIndex: dayIndex,
    parseSchedule: parseSchedule,
    topPriorities: topPriorities,
    currentSlot: currentSlot,
    slotsForDay: slotsForDay,
    dayProgress: dayProgress,
    formatMinutes: formatMinutes,
    formatRemaining: formatRemaining,
    dayName: dayName,
    parseTime: parseTime,
    resolveEnd: resolveEnd,
    updateSlot: updateSlot
  }
}
