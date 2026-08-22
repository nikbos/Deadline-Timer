import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ScheduleModel.js" as ScheduleModel

Panel {
  id: root
  moduleName: "deadline-timer"
  ipcTarget: "deadline-timer"
  manageIpc: false

  property date now: new Date()
  property var schedule: []
  property var topPriorities: []
  property var activeSlot: null
  property int selectedDay: now.getDay()
  property string lastAnnouncedId: ""
  property string lastPriorityCleanupDate: ""
  property bool scheduleLoaded: false
  property bool addingTask: false
  property string taskError: ""
  property bool editingTask: false
  property var editingSlot: null
  property string editError: ""
  property int selectedSlotIndex: -1

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configuredPath: root.scheduleSettingPath()
  readonly property string scheduleFilePath: configuredPath.indexOf("~/") === 0
    ? home + configuredPath.slice(1)
    : configuredPath
  property bool use24HourClock: Qt.locale().timeFormat(Locale.ShortFormat).indexOf("H") >= 0
  readonly property int warningMinutes: Math.max(1, Number(setting("warningMinutes", 5)) || 5)
  readonly property bool notificationsEnabled: setting("notifications", true) !== false
  readonly property bool soundEnabled: setting("sound", true) !== false
  readonly property var selectedSlots: ScheduleModel.slotsForDay(schedule, selectedDay)
  readonly property bool selectedIsToday: selectedDay === now.getDay()
  readonly property string statusText: activeSlot
    ? activeSlot.title + "  " + ScheduleModel.formatRemaining(activeSlot.remainingSeconds)
    : "No active task"
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real panelWidth: Style.space(560)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    scheduleFile.reload()
    root.tick()
  }

  function scheduleSettingPath() {
    return String(setting("schedulePath", "~/.config/omarchy/schedule.md"))
  }

  function loadSchedule(raw) {
    root.schedule = ScheduleModel.parseSchedule(raw)
    root.topPriorities = ScheduleModel.topPriorities(raw, root.selectedDay)
    root.scheduleLoaded = true
    root.selectedSlotIndex = -1
    root.tick()
  }

  function loadClockFormat(raw) {
    try {
      var config = JSON.parse(raw)
      var center = config.bar && config.bar.layout && config.bar.layout.center
      if (!center) return
      for (var i = 0; i < center.length; i++) {
        if (center[i].id !== "omarchy.clock") continue
        var format = String(center[i].format || center[i].verticalFormat || "")
        if (/[Hk]/.test(format)) root.use24HourClock = true
        else if (/[hK]/.test(format)) root.use24HourClock = false
        return
      }
    } catch (error) {
      // Keep the locale-based default when shell.json is unavailable or invalid.
    }
  }

  function tick() {
    var previousDay = root.now.getDay()
    root.now = new Date()
    root.activeSlot = ScheduleModel.currentSlot(root.schedule, root.now)
    root.clearWeeklyPriorities()
    if (previousDay !== root.now.getDay()) {
      root.selectedDay = root.now.getDay()
      root.topPriorities = ScheduleModel.topPriorities(scheduleFile.text(), root.selectedDay)
      root.lastAnnouncedId = ""
    }
    root.checkDeadline()
  }

  function clearWeeklyPriorities() {
    if (root.now.getDay() !== 0 || root.now.getHours() < 18) return
    var dateKey = root.now.getFullYear() + "-" + root.now.getMonth() + "-" + root.now.getDate()
    if (root.lastPriorityCleanupDate === dateKey) return

    var lines = scheduleFile.text().split(/\r?\n/)
    var inDay = false
    var updatedLines = []
    for (var i = 0; i < lines.length; i++) {
      var dayHeading = lines[i].match(/^###\s+([^:]+):/)
      if (dayHeading) {
        inDay = ScheduleModel.dayIndex(dayHeading[1]) >= 0
      } else if (/^#{1,2}\s+/.test(lines[i])) {
        inDay = false
      }
      if (inDay && /^\s*-\s+\[[ xX]\]\s+/.test(lines[i])) continue
      updatedLines.push(lines[i])
    }

    root.lastPriorityCleanupDate = dateKey
    var updatedSchedule = updatedLines.join("\n")
    if (updatedSchedule === scheduleFile.text()) return
    scheduleFile.setText(updatedSchedule)
    root.topPriorities = ScheduleModel.topPriorities(updatedSchedule, root.selectedDay)
  }

  function open() {
    root.tick()
    root.selectedDay = root.now.getDay()
    root.topPriorities = ScheduleModel.topPriorities(scheduleFile.text(), root.selectedDay)
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    root.setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    root.opened ? root.close() : root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function moveDay(delta) {
    root.selectedDay = (root.selectedDay + Number(delta) + 7) % 7
    root.selectedSlotIndex = -1
    root.topPriorities = ScheduleModel.topPriorities(scheduleFile.text(), root.selectedDay)
  }

  function goToToday() {
    root.tick()
    root.selectedDay = root.now.getDay()
    root.selectedSlotIndex = -1
    root.topPriorities = ScheduleModel.topPriorities(scheduleFile.text(), root.selectedDay)
  }

  function startAddTask() {
    root.taskError = ""
    root.editingTask = false
    root.editingSlot = null
    root.editError = ""
    root.addingTask = true
    taskFormScrollTimer.restart()
  }

  function revealTaskForm() {
    timelineFlickable.contentY = Math.max(0, timelineFlickable.contentHeight - timelineFlickable.height)
    taskTitleField.forceActiveFocus()
  }

  function revealEditForm() {
    timelineFlickable.contentY = Math.max(0, timelineFlickable.contentHeight - timelineFlickable.height)
    editTitleField.forceActiveFocus()
  }

  function cancelAddTask() {
    root.addingTask = false
    root.taskError = ""
    taskFormScrollTimer.stop()
    taskTitleField.text = ""
    taskTitleField.focus = false
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function startEditSlot(day, rowIndex) {
    if (root.addingTask) {
      root.addingTask = false
      root.taskError = ""
      taskFormScrollTimer.stop()
      taskTitleField.text = ""
      taskTitleField.focus = false
    }
    var slots = ScheduleModel.slotsForDay(root.schedule, day)
    if (rowIndex < 0 || rowIndex >= slots.length) return
    var slot = slots[rowIndex]
    root.selectedSlotIndex = rowIndex
    root.editingSlot = { day: day, rowIndex: rowIndex }
    editTitleField.text = slot.title
    editStartField.text = ScheduleModel.formatMinutes(slot.start, root.use24HourClock)
    editEndField.text = ScheduleModel.formatMinutes(slot.end, root.use24HourClock)
    root.editError = ""
    root.editingTask = true
    editFormScrollTimer.restart()
  }

  function cancelEditTask() {
    root.editingTask = false
    root.editingSlot = null
    root.editError = ""
    editFormScrollTimer.stop()
    editTitleField.text = ""
    editStartField.text = ""
    editEndField.text = ""
    editTitleField.focus = false
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function saveEditTask() {
    var title = editTitleField.text.replace(/[|\r\n]/g, " ").trim()
    if (!title) {
      root.editError = "Enter a title"
      return
    }

    var start = ScheduleModel.parseTime(editStartField.text)
    if (start === null) {
      root.editError = "Invalid start time"
      return
    }

    var end = ScheduleModel.resolveEnd(start, editEndField.text)
    if (end === null) {
      root.editError = "Invalid end time"
      return
    }

    if (end <= start) {
      root.editError = "End must be after start"
      return
    }

    var updated = ScheduleModel.updateSlot(scheduleFile.text(), root.editingSlot.day, root.editingSlot.rowIndex, start, end, title)
    if (updated === null) {
      root.editError = "Slot no longer exists"
      return
    }

    scheduleFile.setText(updated)
    root.loadSchedule(updated)
    root.cancelEditTask()
  }

  function startEditActiveSlot() {
    if (root.addingTask || root.editingTask) return
    if (root.selectedSlotIndex >= 0 && root.selectedSlotIndex < root.selectedSlots.length) {
      var selected = root.selectedSlots[root.selectedSlotIndex]
      root.startEditSlot(selected.day, root.selectedSlotIndex)
      return
    }
    if (!root.activeSlot) return
    var slots = ScheduleModel.slotsForDay(root.schedule, root.activeSlot.day)
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].id === root.activeSlot.id) {
        root.startEditSlot(root.activeSlot.day, i)
        return
      }
    }
  }

  function moveSlotSelection(delta) {
    var count = root.selectedSlots.length
    if (count === 0) return
    var next = root.selectedSlotIndex < 0
      ? (delta > 0 ? 0 : count - 1)
      : root.selectedSlotIndex + delta
    root.selectedSlotIndex = Math.max(0, Math.min(count - 1, next))
    root.scrollSlotIntoView(root.selectedSlotIndex)
  }

  function scrollSlotIntoView(index) {
    var item = slotRepeater.itemAt(index)
    if (!item) return
    var view = timelineFlickable
    if (item.y < view.contentY) {
      view.contentY = item.y
    } else if (item.y + item.height > view.contentY + view.height) {
      view.contentY = item.y + item.height - view.height
    }
  }

  function saveNewTask() {
    var title = taskTitleField.text.replace(/[|\r\n]/g, " ").trim()
    if (!title) {
      root.taskError = "Enter a top priority"
      return
    }

    var lines = scheduleFile.text().split(/\r?\n/)
    var dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    var dayLine = -1
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].match(new RegExp("^###\\s+" + dayNames[root.selectedDay] + "\\s*:", "i"))) {
        dayLine = i
        break
      }
    }
    if (dayLine < 0) {
      root.taskError = "No schedule found for this day"
      return
    }
    lines.splice(dayLine + 1, 0, "- [ ] " + title)

    var updatedSchedule = lines.join("\n")
    scheduleFile.setText(updatedSchedule)
    root.topPriorities = ScheduleModel.topPriorities(updatedSchedule, root.selectedDay)
    root.cancelAddTask()
  }

  function togglePriority(index) {
    var lines = scheduleFile.text().split(/\r?\n/)
    var dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    var dayLine = -1
    var priorityIndex = 0
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].match(new RegExp("^###\\s+" + dayNames[root.selectedDay] + "\\s*:", "i"))) {
        dayLine = i
        break
      }
    }
    if (dayLine < 0) return
    for (var j = dayLine + 1; j < lines.length; j++) {
      if (/^###\s+/.test(lines[j])) break
      if (/^\s*-\s+\[[ xX]\]\s+/.test(lines[j])) {
        if (priorityIndex === index) {
          lines[j] = lines[j].replace(/\[([ xX])\]/, function(_, mark) {
            return mark.toLowerCase() === "x" ? "[ ]" : "[x]"
          })
          break
        }
        priorityIndex++
      }
    }
    var updatedSchedule = lines.join("\n")
    scheduleFile.setText(updatedSchedule)
    root.topPriorities = ScheduleModel.topPriorities(updatedSchedule, root.selectedDay)
  }

  function completeTopPriority() {
    for (var i = 0; i < root.topPriorities.length; i++) {
      if (!root.topPriorities[i].done) {
        root.togglePriority(i)
        return
      }
    }
  }

  function categoryColor(category) {
    if (category === "deep-work") return Color.accent
    if (category === "movement") return Color.urgent
    if (category === "meal") return Qt.lighter(Color.accent, 1.25)
    if (category === "rest") return Qt.darker(Color.accent, 1.35)
    if (category === "learning") return Qt.lighter(contentForeground, 1.3)
    if (category === "life") return Qt.darker(Color.urgent, 1.25)
    if (category === "admin") return Qt.darker(Color.accent, 1.55)
    return Qt.darker(contentForeground, 1.55)
  }

  function slotState(slot) {
    if (selectedIsToday && activeSlot && slot.id === activeSlot.id) return "current"
    if (selectedIsToday && slot.end <= now.getHours() * 60 + now.getMinutes()) return "past"
    return "future"
  }

  function checkDeadline() {
    if (!root.activeSlot || !root.notificationsEnabled) return
    if (root.activeSlot.remainingSeconds > root.warningMinutes * 60) return
    if (root.lastAnnouncedId === root.activeSlot.id) return

    root.lastAnnouncedId = root.activeSlot.id
    if (!root.bar || !root.bar.run) return
    var message = root.activeSlot.title + " - "
      + ScheduleModel.formatRemaining(root.activeSlot.remainingSeconds) + " remaining"
    root.bar.run("notify-send -a deadline-timer " + Util.shellQuote("Deadline approaching")
      + " " + Util.shellQuote(message))
    if (root.soundEnabled)
      root.bar.run("canberra-gtk-play --id=alarm-clock-elapsed")
  }

  function handleMove(dx, dy) {
    if (dx !== 0) root.moveDay(dx)
    if (dy !== 0) root.moveSlotSelection(dy)
  }

  FileView {
    id: scheduleFile
    path: root.scheduleFilePath
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSchedule(text())
    onFileChanged: reload()
    onLoadFailed: root.loadSchedule("")
  }

  FileView {
    id: shellConfigFile
    path: home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadClockFormat(text())
    onFileChanged: reload()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.tick()
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Timer {
    id: taskFormScrollTimer
    interval: 75
    repeat: false
    onTriggered: root.revealTaskForm()
  }

  Timer {
    id: editFormScrollTimer
    interval: 75
    repeat: false
    onTriggered: root.revealEditForm()
  }

  IpcHandler {
    target: "deadline-timer"
    function refresh(): void { root.refresh() }
    function today(): void { root.goToToday() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.statusText
    labelVisible: true
    hasVisualContent: true
    active: !!root.activeSlot
    activeColor: root.activeSlot && root.activeSlot.remainingSeconds <= root.warningMinutes * 60
      ? Color.urgent
      : root.categoryColor(root.activeSlot ? root.activeSlot.category : "other")
    tooltipText: root.statusText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }

  Component.onCompleted: Qt.callLater(function() {
    scheduleFile.reload()
    shellConfigFile.reload()
  })

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(root.panelWidth)
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.addingTask || root.editingTask
      onMoveRequested: function(dx, dy) { root.handleMove(dx, dy) }
      onActivateRequested: root.startEditActiveSlot()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.goToToday()
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "n" || t === "N") root.startAddTask()
        else if (t === "d" || t === "D") root.completeTopPriority()
        else if (t === "[" || t === "h") root.moveDay(-1)
        else if (t === "]" || t === "l") root.moveDay(1)
      }

      Flickable {
        id: timelineFlickable
        anchors.fill: parent
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: Math.max(1, timelineFlickable.width)
          spacing: Style.space(12)

          Item {
            width: parent.width
            height: heroColumn.implicitHeight

            Column {
              id: heroColumn
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.selectedIsToday && root.activeSlot ? "ACTIVE NOW" : ScheduleModel.dayName(root.selectedDay)
                color: root.activeSlot && root.selectedIsToday ? Color.accent : Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.5
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.selectedIsToday && root.activeSlot
                  ? ScheduleModel.formatRemaining(root.activeSlot.remainingSeconds)
                  : (root.selectedSlots.length > 0 ? "SCHEDULE" : "NO SCHEDULE")
                color: root.activeSlot && root.selectedIsToday
                  ? (root.activeSlot.remainingSeconds <= root.warningMinutes * 60 ? Color.urgent : root.contentForeground)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: root.activeSlot && root.selectedIsToday ? Style.font.displayLarge : Style.font.title
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.selectedIsToday && root.activeSlot ? root.activeSlot.title : ""
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: contentColumn.width - Style.space(24)
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

            Item {
              width: parent.width
              height: priorityColumn.implicitHeight + Style.space(14)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.16)
                border.width: Style.spacing.hairline
              }

              Column {
                id: priorityColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
               anchors.leftMargin: Style.space(12)
               anchors.rightMargin: Style.space(12)
                spacing: Style.space(3)

                Text {
                  text: "TOP PRIORITIES"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.8
                }

                Repeater {
                  model: root.topPriorities

                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: priorityColumn.width
                    height: priorityRow.implicitHeight

                    Row {
                      id: priorityRow
                      width: parent.width
                      spacing: Style.space(8)

                      Rectangle {
                        width: Style.space(14)
                        height: width
                        radius: Style.cornerRadius > 0 ? Style.space(2) : 0
                        color: modelData.done ? Color.accent : "transparent"
                        border.color: modelData.done ? Color.accent : Qt.darker(root.contentForeground, 1.4)
                        border.width: Style.spacing.hairline

                        Text {
                          anchors.centerIn: parent
                          text: "✓"
                          visible: modelData.done
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      Text {
                        width: parent.width - Style.space(22)
                        text: modelData.title
                        color: modelData.done ? Qt.darker(root.contentForeground, 1.6) : root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.strikeout: modelData.done
                        elide: Text.ElideRight
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.togglePriority(index)
                    }
                  }
                }

                Text {
                  visible: root.topPriorities.length === 0
                  width: parent.width
                  text: "No top priorities yet"
                  color: Qt.darker(root.contentForeground, 1.6)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            Row {
              width: parent.width
              height: dayLabel.implicitHeight + Style.space(8)

              PanelActionButton {
                iconText: "󰅁"
                tooltipText: "Previous day"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveDay(-1)
              }

              Text {
                id: dayLabel
                width: parent.width - Style.space(80)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.selectedDay === root.now.getDay() ? "TODAY" : ScheduleModel.dayName(root.selectedDay)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                font.letterSpacing: 1
              }

              PanelActionButton {
                iconText: "󰅂"
                tooltipText: "Next day"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveDay(1)
              }
            }

          Repeater {
            id: slotRepeater
            model: root.selectedSlots

            delegate: Item {
              required property var modelData
              required property int index
              width: contentColumn.width
              height: slotRow.implicitHeight + Style.space(10)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: index === root.selectedSlotIndex
                  ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
                  : "transparent"
                border.width: index === root.selectedSlotIndex ? Style.spacing.hairline : 0
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.35)
              }

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.space(4)
                radius: Style.space(2)
                color: root.categoryColor(modelData.category)
                opacity: root.slotState(modelData) === "past" ? 0.35 : 1
              }

              Row {
                id: slotRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                spacing: Style.space(12)

                Column {
                  width: Style.space(100)
                  spacing: Style.space(2)

                  Text {
                    text: ScheduleModel.formatMinutes(modelData.start, root.use24HourClock)
                    color: root.slotState(modelData) === "current"
                      ? root.categoryColor(modelData.category)
                      : Qt.darker(root.contentForeground, 1.45)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: root.slotState(modelData) === "current"
                  }

                  Text {
                    text: ScheduleModel.formatMinutes(modelData.end, root.use24HourClock)
                    color: Qt.darker(root.contentForeground, 1.8)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  width: parent.width - Style.space(112)
                  spacing: Style.space(4)

                  Text {
                    text: modelData.title
                    width: parent.width
                    color: root.slotState(modelData) === "past" ? Qt.darker(root.contentForeground, 1.7) : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: root.slotState(modelData) === "current"
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    visible: root.slotState(modelData) === "current"
                    width: parent.width
                    height: Style.space(4)
                    radius: Style.cornerRadius > 0 ? height / 2 : 0
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                    Rectangle {
                      width: parent.width * (root.activeSlot ? root.activeSlot.progress : 0)
                      height: parent.height
                      radius: parent.radius
                      color: root.activeSlot && root.activeSlot.remainingSeconds <= root.warningMinutes * 60
                        ? Color.urgent : root.categoryColor(modelData.category)
                    }
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedSlotIndex = index
                  root.startEditSlot(modelData.day, index)
                }
              }
            }

          }

           Text {
              visible: root.selectedSlots.length === 0
              width: parent.width
              text: "No schedule found for this day"
              horizontalAlignment: Text.AlignHCenter
              color: Qt.darker(root.contentForeground, 1.6)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }

          Item {
              width: parent.width
              height: Style.space(28)
              visible: !root.addingTask && !root.editingTask

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: newTaskButton.containsMouse
                  ? Style.hoverFillFor(root.contentForeground, Color.accent)
                  : "transparent"
              }

              Text {
                anchors.centerIn: parent
                text: "+ New task"
                color: newTaskButton.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 0.5
              }

              MouseArea {
                id: newTaskButton
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startAddTask()
              }
            }

Column {
              visible: root.addingTask || root.editingTask
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: parent.width
                height: Style.spacing.hairline
                color: root.contentForeground
                opacity: 0.08
              }

              Text {
                visible: root.addingTask
                text: "NEW TOP PRIORITY"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              TextField {
                id: taskTitleField
                visible: root.addingTask
                width: parent.width
                placeholderText: "Task name"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.saveNewTask()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.cancelAddTask()
                    event.accepted = true
                  }
                }
              }

              Text {
                visible: root.addingTask && root.taskError !== ""
                text: root.taskError
                color: Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                visible: root.addingTask
                spacing: Style.space(8)

                PanelActionButton {
                  iconText: "󰄬"
                  tooltipText: "Save task"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.saveNewTask()
                }

                PanelActionButton {
                  iconText: "󰅖"
                  tooltipText: "Cancel"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.cancelAddTask()
                }
              }

              Column {
                visible: root.editingTask
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "EDIT SLOT"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                TextField {
                  id: editTitleField
                  width: parent.width
                  placeholderText: "Slot title"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.saveEditTask()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                      root.cancelEditTask()
                      event.accepted = true
                    }
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  TextField {
                    id: editStartField
                    width: parent.width / 2 - Style.space(4)
                    placeholderText: "Start, e.g. 8:00 or 8:00 AM"
                    inputMethodHints: Qt.ImhTime
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.saveEditTask()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Escape) {
                        root.cancelEditTask()
                        event.accepted = true
                      }
                    }
                  }

                  TextField {
                    id: editEndField
                    width: parent.width / 2 - Style.space(4)
                    placeholderText: "End (blank = 30 min)"
                    inputMethodHints: Qt.ImhTime
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.saveEditTask()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Escape) {
                        root.cancelEditTask()
                        event.accepted = true
                      }
                    }
                  }
                }

                Text {
                  visible: root.editError !== ""
                  text: root.editError
                  color: Color.urgent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  spacing: Style.space(8)

                  PanelActionButton {
                    iconText: "󰄬"
                    tooltipText: "Save slot"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: root.saveEditTask()
                  }

                  PanelActionButton {
                    iconText: "󰅖"
                    tooltipText: "Cancel"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: root.cancelEditTask()
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: bottomProgressLabel.height + bottomProgressTrack.height + Style.space(8)

              Text {
                id: bottomProgressLabel
                anchors.left: parent.left
                text: "DAY PROGRESS"
                color: Qt.darker(root.contentForeground, 1.6)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Text {
                anchors.right: parent.right
                text: Math.round(ScheduleModel.dayProgress(root.now) * 100) + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                id: bottomProgressTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: bottomProgressLabel.bottom
                anchors.topMargin: Style.space(5)
                height: Style.space(5)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: parent.width * ScheduleModel.dayProgress(root.now)
                  height: parent.height
                  radius: parent.radius
                  color: Color.accent
                  Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
              }
            }
        }
      }
    }
  }
}
