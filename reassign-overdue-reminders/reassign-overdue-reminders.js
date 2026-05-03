#!/usr/bin/osascript -l JavaScript
/**
 * Reassign Due Dates for Incomplete Reminders (JXA + Swift helper)
 *
 * Run: osascript -l JavaScript /path/to/reassign-overdue-reminders.js
 *
 * Quick triage: Quit (also Esc), Tomorrow, More… (1 hour and other presets are under More).
 * chooseFromList Esc/Cancel: follow-up asks Stop run vs Skip this one (not silent skip).
 * Uses list-reminders with --overdue --include-notes when the helper supports it.
 */

// Set true to log intended updates without writing to Reminders.
var DRY_RUN = false;

// --- Standard Additions (dialogs / choose from list) ---
var sa = Application.currentApplication();
sa.includeStandardAdditions = true;

ObjC.import("Foundation");

function log(msg) {
  console.log("[reassign-reminders] " + msg);
}

function notifyUser(body, title) {
  try {
    sa.displayNotification(body, {
      withTitle: title || dlgTitle(),
    });
  } catch (e) {}
}

function dlgTitle() {
  return (DRY_RUN ? "[DRY RUN] " : "") + "Overdue reminders";
}

function helperSearchPathsText() {
  return (
    "Helper search order:\n" +
    "• ~/scripts/reassign-overdue-reminders/list-reminders\n" +
    "• …/list-reminders.swift (xcrun swift)\n" +
    "• ~/scripts/list-reminders (same pair)"
  );
}

function truncate(s, max) {
  if (s === null || s === undefined) return "";
  s = String(s);
  if (s.length <= max) return s;
  return s.slice(0, Math.max(0, max - 1)) + "…";
}

/** Calendar-day difference: how many local midnights ago the due date was (approx for UX). */
function formatRelativeOverdue(due, now) {
  if (!due || isNaN(due.getTime())) return "";
  var startDue = new Date(due.getTime());
  startDue.setHours(0, 0, 0, 0);
  var startNow = new Date(now.getTime());
  startNow.setHours(0, 0, 0, 0);
  var diffDays = Math.round((startNow - startDue) / 86400000);
  if (diffDays <= 0) {
    if (now.getTime() > due.getTime()) return "earlier today";
    return "today";
  }
  if (diffDays === 1) return "1 day ago";
  return diffDays + " days ago";
}

function buildReminderPromptBody(item, index1, total) {
  var due = item.originalDueDate;
  var now = new Date();
  var lines = [
    "Item " + index1 + " of " + total,
    "List: " + (item.calendarTitle || "(default)"),
    "Was due: " +
      formatDateTime(due) +
      " (" +
      formatRelativeOverdue(due, now) +
      ")",
  ];
  var note = item.notesSnippet;
  if (note) {
    lines.push("Notes: " + truncate(note.replace(/\s+/g, " ").trim(), 120));
  }
  return lines.join("\n");
}

function humanizeChoiceForBulk(choice, customDate) {
  if (choice === "Custom" && customDate) return formatDateTime(customDate);
  return choice || "";
}

function promptShortConsent() {
  try {
    sa.displayDialog(
      "This reads and updates Apple Reminders on this Mac. Continue?",
      {
        withTitle: dlgTitle(),
        buttons: ["Cancel", "Continue"],
        defaultButton: "Continue",
      }
    );
    return true;
  } catch (e) {
    log("Consent canceled or dismissed.");
    return false;
  }
}

function promptIntroContinue(count) {
  try {
    sa.displayDialog(
      "You have " +
        count +
        " overdue (due before today), oldest first.\n\nContinue?",
      {
        withTitle: dlgTitle(),
        buttons: ["Cancel", "Continue"],
        defaultButton: "Continue",
      }
    );
    return true;
  } catch (e) {
    log("Intro canceled.");
    return false;
  }
}

function promptEmptyDone() {
  try {
    sa.displayDialog("Nothing overdue before today.", {
      withTitle: dlgTitle(),
      buttons: ["OK"],
      defaultButton: "OK",
    });
  } catch (e) {}
}

function promptHelperError() {
  var msg =
    "The reminders helper failed or was not found.\n\n" +
    helperSearchPathsText() +
    "\n\nRebuild or fix the helper. There is no Reminders.app UI fallback.";
  log(msg);
  try {
    sa.displayDialog(msg, {
      withTitle: dlgTitle(),
      buttons: ["OK"],
      defaultButton: "OK",
    });
  } catch (e2) {}
}

function resolveListCancel() {
  try {
    var r = sa.displayDialog(
      "The list was canceled (Esc). Stop the whole run, or skip only this reminder?",
      {
        withTitle: dlgTitle(),
        buttons: ["Skip this one", "Stop run"],
        defaultButton: "Stop run",
      }
    );
    if (r.buttonReturned === "Stop run") return "stop_run";
    return "skip_item";
  } catch (e) {
    return "stop_run";
  }
}

function promptFullChoiceList(itemTitle, body) {
  var items = [
    "10 min",
    "30 min",
    "1 hour",
    "Today",
    "Tomorrow",
    "Monday",
    "Custom",
    "Skip",
    "Stop run",
  ];
  var choice = sa.chooseFromList(items, {
    withTitle: truncate(itemTitle, 80),
    withPrompt: body + "\n\nChoose how to reschedule:",
    defaultItems: ["Tomorrow"],
    OKButtonName: "OK",
    cancelButtonName: "Cancel",
  });

  if (choice === false) {
    var r = resolveListCancel();
    if (r === "stop_run") return { kind: "stop_run" };
    return { kind: "skip" };
  }
  return { kind: "choice", value: choice[0] };
}

function promptQuickTriage(itemTitle, body) {
  var text =
    body +
    "\n\nTip: 1 hour, 10 min, Today, Monday, Custom, etc. are under More…";
  try {
    var r = sa.displayDialog(text, {
      withTitle: truncate(itemTitle, 120),
      buttons: ["Quit", "More…", "Tomorrow"],
      defaultButton: "Tomorrow",
      cancelButton: "Quit",
    });
    var b = r.buttonReturned;
    if (b === "Quit") return { kind: "stop_run" };
    if (b === "Tomorrow") return { kind: "choice", value: "Tomorrow" };
    if (b === "More…") return { kind: "more" };
  } catch (e) {
    log("Quick triage dismissed: " + e);
    return { kind: "stop_run" };
  }
  return { kind: "stop_run" };
}

function promptBulkSameChoice(label, remaining) {
  try {
    var r = sa.displayDialog(
      "Apply " +
        label +
        " to all " +
        remaining +
        " remaining reminder" +
        (remaining === 1 ? "" : "s") +
        "?",
      {
        withTitle: dlgTitle(),
        buttons: ["Stop", "Each", "All"],
        defaultButton: "Each",
      }
    );
    var b = r.buttonReturned;
    if (b === "All") return "all";
    if (b === "Stop") return "stop";
    return "each";
  } catch (e) {
    return "each";
  }
}

function toJSDate(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return new Date(value.getTime());
  try {
    var d = new Date(value);
    if (!isNaN(d.getTime())) return d;
  } catch (e) {}
  return null;
}

function startOfToday() {
  var d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

function addMinutes(date, minutes) {
  var x = new Date(date.getTime());
  x.setMinutes(x.getMinutes() + minutes);
  return x;
}

function combineDateWithTime(datePart, timeSourceDate) {
  var base = new Date(datePart.getTime());
  base.setHours(
    timeSourceDate.getHours(),
    timeSourceDate.getMinutes(),
    timeSourceDate.getSeconds(),
    timeSourceDate.getMilliseconds()
  );
  return base;
}

function nextMondayFromToday() {
  var todayStart = startOfToday();
  var d = new Date(todayStart);
  d.setDate(d.getDate() + 1);
  while (d.getDay() !== 1) {
    d.setDate(d.getDate() + 1);
  }
  return d;
}

function tomorrowDate() {
  var t = new Date(startOfToday());
  t.setDate(t.getDate() + 1);
  return t;
}

function formatDateTime(d) {
  if (!d || isNaN(d.getTime())) return "(invalid)";
  return d.toLocaleString();
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n;
}

function defaultDateString(d) {
  return (
    d.getFullYear() +
    "-" +
    pad2(d.getMonth() + 1) +
    "-" +
    pad2(d.getDate())
  );
}

function defaultTimeString(d) {
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function promptForCustomDate(originalDueDate) {
  var dateDefault = defaultDateString(originalDueDate);
  var timeDefault = defaultTimeString(originalDueDate);

  var dr;
  try {
    dr = sa.displayDialog(
      "Date (YYYY-MM-DD). Time is next; you can keep the original time.",
      {
        defaultAnswer: dateDefault,
        withTitle: "Custom due date",
        buttons: ["Cancel", "OK"],
        defaultButton: "OK",
      }
    );
  } catch (e) {
    return { canceled: true, date: null };
  }
  if (dr.buttonReturned !== "OK") return { canceled: true, date: null };

  var datePart = new Date(dr.textReturned + "T12:00:00");
  if (isNaN(datePart.getTime())) {
    try {
      sa.displayDialog("Could not parse date.", {
        withTitle: "Invalid date",
        buttons: ["OK"],
        defaultButton: "OK",
      });
    } catch (e2) {}
    return { canceled: true, date: null };
  }

  var tr;
  try {
    tr = sa.displayDialog(
      "Time (24h HH:MM), or leave as-is for original time.",
      {
        defaultAnswer: timeDefault,
        withTitle: "Custom due time",
        buttons: ["Cancel", "OK"],
        defaultButton: "OK",
      }
    );
  } catch (e) {
    return { canceled: true, date: null };
  }
  if (tr.buttonReturned !== "OK") return { canceled: true, date: null };

  var m = tr.textReturned.match(/^(\d{1,2}):(\d{2})$/);
  var hours = originalDueDate.getHours();
  var minutes = originalDueDate.getMinutes();
  if (m) {
    hours = parseInt(m[1], 10);
    minutes = parseInt(m[2], 10);
    if (
      hours < 0 ||
      hours > 23 ||
      minutes < 0 ||
      minutes > 59 ||
      isNaN(hours) ||
      isNaN(minutes)
    ) {
      try {
        sa.displayDialog("Invalid time; use HH:MM (24h).", {
          withTitle: "Invalid time",
          buttons: ["OK"],
          defaultButton: "OK",
        });
      } catch (e3) {}
      return { canceled: true, date: null };
    }
  }

  var y = datePart.getFullYear();
  var mo = datePart.getMonth();
  var da = datePart.getDate();
  var result = new Date(y, mo, da, hours, minutes, 0, 0);
  return { canceled: false, date: result };
}

function computeNewDueDate(choice, originalDueDate, now) {
  if (choice === "10 min") return addMinutes(now, 10);
  if (choice === "30 min") return addMinutes(now, 30);
  if (choice === "1 hour") return addMinutes(now, 60);

  if (choice === "Today") {
    var t = combineDateWithTime(startOfToday(), originalDueDate);
    if (t.getTime() < now.getTime()) return addMinutes(now, 10);
    return t;
  }

  if (choice === "Tomorrow") {
    return combineDateWithTime(tomorrowDate(), originalDueDate);
  }

  if (choice === "Monday") {
    return combineDateWithTime(nextMondayFromToday(), originalDueDate);
  }

  return null;
}

function shSingleQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function overdueFetchShellCommand() {
  var home = ObjC.unwrap($.NSHomeDirectory());
  var b1 = home + "/scripts/reassign-overdue-reminders/list-reminders";
  var s1 = home + "/scripts/reassign-overdue-reminders/list-reminders.swift";
  var b2 = home + "/scripts/list-reminders";
  var s2 = home + "/scripts/list-reminders.swift";
  var overdueFlags = " --overdue --include-notes";
  return (
    "if [ -x " +
    shSingleQuote(b1) +
    " ]; then " +
    shSingleQuote(b1) +
    overdueFlags +
    "; elif [ -f " +
    shSingleQuote(s1) +
    " ]; then /usr/bin/xcrun swift " +
    shSingleQuote(s1) +
    overdueFlags +
    "; elif [ -x " +
    shSingleQuote(b2) +
    " ]; then " +
    shSingleQuote(b2) +
    overdueFlags +
    "; elif [ -f " +
    shSingleQuote(s2) +
    " ]; then /usr/bin/xcrun swift " +
    shSingleQuote(s2) +
    overdueFlags +
    "; else exit 127; fi"
  );
}

function setDueShellCommand(id, unixSecsRounded, dryRun) {
  var home = ObjC.unwrap($.NSHomeDirectory());
  var b1 = home + "/scripts/reassign-overdue-reminders/list-reminders";
  var s1 = home + "/scripts/reassign-overdue-reminders/list-reminders.swift";
  var b2 = home + "/scripts/list-reminders";
  var s2 = home + "/scripts/list-reminders.swift";
  var dry = dryRun ? " --dry-run" : "";
  var idQ = shSingleQuote(id);
  return (
    "if [ -x " +
    shSingleQuote(b1) +
    " ]; then " +
    shSingleQuote(b1) +
    " --set-due " +
    idQ +
    " " +
    unixSecsRounded +
    dry +
    "; elif [ -f " +
    shSingleQuote(s1) +
    " ]; then /usr/bin/xcrun swift " +
    shSingleQuote(s1) +
    " --set-due " +
    idQ +
    " " +
    unixSecsRounded +
    dry +
    "; elif [ -x " +
    shSingleQuote(b2) +
    " ]; then " +
    shSingleQuote(b2) +
    " --set-due " +
    idQ +
    " " +
    unixSecsRounded +
    dry +
    "; elif [ -f " +
    shSingleQuote(s2) +
    " ]; then /usr/bin/xcrun swift " +
    shSingleQuote(s2) +
    " --set-due " +
    idQ +
    " " +
    unixSecsRounded +
    dry +
    "; else exit 127; fi"
  );
}

/**
 * @returns {Array<{id:string,title:string,calendarTitle:string,originalDueDate:Date,notesSnippet:string}>} | null
 */
function tryFetchOverdueViaSwift() {
  var t0 = Date.now();
  var jsonText;
  try {
    jsonText = sa.doShellScript(overdueFetchShellCommand());
  } catch (e) {
    log("Swift list-reminders fetch failed: " + e);
    return null;
  }
  if (jsonText === null || jsonText === undefined || jsonText === "") {
    log("Swift helper returned empty stdout.");
    return null;
  }
  var rows;
  try {
    rows = JSON.parse(jsonText);
  } catch (e) {
    log("Swift JSON parse failed: " + e);
    return null;
  }
  if (!rows || !rows.length) {
    log("Swift helper returned 0 overdue in " + (Date.now() - t0) + " ms.");
    return [];
  }
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    if (!row || !row.id) continue;
    var due = row.dueDate ? new Date(row.dueDate) : null;
    if (!due || isNaN(due.getTime())) continue;
    var notes = row.notes != null ? String(row.notes) : "";
    out.push({
      id: row.id,
      title: row.title || "(Untitled)",
      calendarTitle: row.calendarTitle || "",
      originalDueDate: due,
      notesSnippet: notes,
    });
  }
  log("Parsed " + out.length + " overdue row(s) in " + (Date.now() - t0) + " ms.");
  return out;
}

function getOverdueWorkItems() {
  var swiftRows = tryFetchOverdueViaSwift();
  if (swiftRows === null) return null;
  return swiftRows;
}

function applySwiftDueDate(id, newDueDate, dryRun) {
  var secs = String(Math.round(newDueDate.getTime() / 1000));
  sa.doShellScript(setDueShellCommand(id, secs, dryRun));
}

function updateWorkItemDueDate(item, newDueDate, dryRun) {
  var name = item.title || "(Reminder)";
  var oldDue = item.originalDueDate;
  if (dryRun) {
    log(
      "[DRY_RUN] Would set \"" +
        name +
        "\" due " +
        formatDateTime(oldDue) +
        " -> " +
        formatDateTime(newDueDate)
    );
    return;
  }
  applySwiftDueDate(item.id, newDueDate, false);
  log(
    "Updated \"" +
      name +
      "\" due " +
      formatDateTime(oldDue) +
      " -> " +
      formatDateTime(newDueDate)
  );
}

/**
 * Triage one reminder: returns
 * { result: 'stop' } | { result: 'skip' } |
 * { result: 'ok', choice, newDue, replaySpec }
 */
function triageReminderOnce(item, index1, total) {
  var body = buildReminderPromptBody(item, index1, total);
  var title = item.title || "(Reminder)";

  var step = promptQuickTriage(title, body);
  if (step.kind === "stop_run") return { result: "stop" };
  var choice = null;
  if (step.kind === "choice") {
    choice = step.value;
  } else if (step.kind === "more") {
    var full = promptFullChoiceList(title, body);
    if (full.kind === "stop_run") return { result: "stop" };
    if (full.kind === "skip") return { result: "skip" };
    choice = full.value;
  }

  if (choice === "Stop run") return { result: "stop" };
  if (choice === "Skip") return { result: "skip" };

  var newDue = null;
  if (choice === "Custom") {
    var custom = promptForCustomDate(item.originalDueDate);
    if (custom.canceled) return { result: "skip" };
    newDue = custom.date;
  } else {
    newDue = computeNewDueDate(choice, item.originalDueDate, new Date());
  }

  if (!newDue || isNaN(newDue.getTime())) {
    return { result: "skip" };
  }

  var replaySpec;
  if (choice === "Custom") {
    replaySpec = { type: "custom", date: new Date(newDue.getTime()) };
  } else {
    replaySpec = { type: "preset", choice: choice };
  }
  return { result: "ok", choice: choice, newDue: newDue, replaySpec: replaySpec };
}

function computeReplayDue(replaySpec, workItem) {
  var now = new Date();
  if (replaySpec.type === "custom") {
    return new Date(replaySpec.date.getTime());
  }
  return computeNewDueDate(
    replaySpec.choice,
    workItem.originalDueDate,
    now
  );
}

function run() {
  log("Starting.");
  if (!promptShortConsent()) return;

  var overdue = getOverdueWorkItems();
  if (overdue === null) {
    promptHelperError();
    return;
  }
  if (overdue.length === 0) {
    promptEmptyDone();
    return;
  }
  if (!promptIntroContinue(overdue.length)) return;

  notifyUser(
    "Found " + overdue.length + " overdue. Starting triage…",
    dlgTitle()
  );

  var updatedCount = 0;
  var skippedCount = 0;
  var errorCount = 0;
  var notReviewed = 0;

  var i = 0;
  while (i < overdue.length) {
    var item = overdue[i];
    var originalDueDate = item.originalDueDate;
    if (!originalDueDate || isNaN(originalDueDate.getTime())) {
      skippedCount++;
      log("Skipping item with missing due date.");
      i++;
      continue;
    }

    var index1 = i + 1;
    var tri = triageReminderOnce(item, index1, overdue.length);
    if (tri.result === "stop") {
      notReviewed = overdue.length - i;
      log("Stop run.");
      break;
    }
    if (tri.result === "skip") {
      skippedCount++;
      i++;
      continue;
    }

    try {
      updateWorkItemDueDate(item, tri.newDue, DRY_RUN);
      updatedCount++;
    } catch (e) {
      errorCount++;
      log("Error updating \"" + (item.title || "") + "\": " + e);
      i++;
      continue;
    }

    var remainingAfterThis = overdue.length - i - 1;
    if (remainingAfterThis > 0) {
      var label =
        '"' + humanizeChoiceForBulk(tri.choice, tri.newDue) + '"';
      var bulk = promptBulkSameChoice(label, remainingAfterThis);
      if (bulk === "stop") {
        notReviewed = remainingAfterThis;
        log("Bulk: stop.");
        break;
      }
      if (bulk === "all") {
        var spec = tri.replaySpec;
        for (var j = i + 1; j < overdue.length; j++) {
          var it2 = overdue[j];
          if (!it2.originalDueDate || isNaN(it2.originalDueDate.getTime())) {
            skippedCount++;
            continue;
          }
          var nd = computeReplayDue(spec, it2);
          if (!nd || isNaN(nd.getTime())) {
            errorCount++;
            continue;
          }
          try {
            updateWorkItemDueDate(it2, nd, DRY_RUN);
            updatedCount++;
          } catch (e2) {
            errorCount++;
            log("Bulk update error: " + e2);
          }
        }
        i = overdue.length;
        break;
      }
    }

    i++;
  }

  var summaryParts = [];
  summaryParts.push("Updated " + updatedCount + ".");
  summaryParts.push("Skipped " + skippedCount + ".");
  if (errorCount) summaryParts.push("Errors: " + errorCount + ".");
  if (notReviewed > 0) {
    summaryParts.push("Closed early: " + notReviewed + " not reviewed.");
  }
  if (DRY_RUN) summaryParts.push("(No changes saved; DRY_RUN is on.)");

  var summary = summaryParts.join(" ");
  log(summary);

  try {
    sa.displayDialog(summary, {
      withTitle: dlgTitle(),
      buttons: ["OK"],
      defaultButton: "OK",
    });
  } catch (e) {
    log("Summary dialog failed: " + e);
  }
}

run();
