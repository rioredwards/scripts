#!/usr/bin/osascript -l JavaScript
/**
 * Reassign Due Dates for Incomplete Reminders (JXA + Swift helper)
 *
 * Run: osascript -l JavaScript /path/to/reassign-overdue-reminders.js
 *
 * Uses the EventKit helper next to this script when possible:
 *   ~/scripts/reassign-overdue-reminders/list-reminders
 *   ~/scripts/reassign-overdue-reminders/list-reminders.swift
 * or the same filenames under ~/scripts/. There is no slow Reminders.app
 * fallback; if the helper fails, the script exits after an error dialog.
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

/** Optional; fails silently if notifications are denied. */
function notifyUser(body, title) {
  try {
    sa.displayNotification(body, {
      withTitle: title || "Reassign overdue reminders",
    });
  } catch (e) {}
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
  var d = new Date(date.getTime());
  d.setMinutes(d.getMinutes() + minutes);
  return d;
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

/** Next calendar Monday strictly after today's date (if today is Mon, following Mon). */
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

function promptForChoice(title, dueStr) {
  var items = [
    "10 min",
    "30 min",
    "1 hour",
    "Today",
    "Tomorrow",
    "Monday",
    "Custom",
    "Skip",
    "Quit",
  ];

  var prompt =
    "Due: " + (dueStr || "unknown") + "\n\nChoose how to reschedule:";
  var choice = sa.chooseFromList(items, {
    withTitle: title || "(Reminder)",
    withPrompt: prompt,
    defaultItems: ["Skip"],
    OKButtonName: "OK",
    cancelButtonName: "Cancel",
  });

  if (choice === false) return { canceled: true, value: null };
  return { canceled: false, value: choice[0] };
}

function promptForCustomDate(originalDueDate) {
  var dateDefault = defaultDateString(originalDueDate);
  var timeDefault = defaultTimeString(originalDueDate);

  var dr;
  try {
    dr = sa.displayDialog(
      "Enter date (YYYY-MM-DD). Time is asked next; you can keep the reminder's original time.",
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
      "Enter time (24h HH:MM) or leave as-is for original time.",
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
  return (
    "if [ -x " +
    shSingleQuote(b1) +
    " ]; then " +
    shSingleQuote(b1) +
    " --overdue; elif [ -f " +
    shSingleQuote(s1) +
    " ]; then /usr/bin/xcrun swift " +
    shSingleQuote(s1) +
    " --overdue; elif [ -x " +
    shSingleQuote(b2) +
    " ]; then " +
    shSingleQuote(b2) +
    " --overdue; elif [ -f " +
    shSingleQuote(s2) +
    " ]; then /usr/bin/xcrun swift " +
    shSingleQuote(s2) +
    " --overdue; else exit 127; fi"
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
 * @returns {Array<{id:string,title:string,calendarTitle:string,originalDueDate:Date}>} on success
 * @returns {null} if the helper failed or stdout was unusable
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
    log("Swift helper returned 0 overdue reminder(s) in " + (Date.now() - t0) + " ms.");
    return [];
  }
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    if (!row || !row.id) continue;
    var due = row.dueDate ? new Date(row.dueDate) : null;
    if (!due || isNaN(due.getTime())) continue;
    out.push({
      id: row.id,
      title: row.title || "(Untitled)",
      calendarTitle: row.calendarTitle || "",
      originalDueDate: due,
    });
  }
  log(
    "Swift helper parsed " +
      out.length +
      " overdue row(s) in " +
      (Date.now() - t0) +
      " ms."
  );
  return out;
}

function getOverdueWorkItems() {
  var swiftRows = tryFetchOverdueViaSwift();
  if (swiftRows === null) {
    return null;
  }
  return swiftRows.map(function (r) {
    return {
      id: r.id,
      title: r.title,
      calendarTitle: r.calendarTitle,
      originalDueDate: r.originalDueDate,
    };
  });
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

function run() {
  log("Ready. Showing start dialog (if you see nothing, check behind other windows).");
  try {
    sa.displayDialog(
      "This tool needs the EventKit helper (list-reminders) to load and save reminders. It does not use the slow Reminders UI scripting path.\n\nHelper search order:\n• ~/scripts/reassign-overdue-reminders/list-reminders\n• …/list-reminders.swift (via xcrun swift)\n• ~/scripts/list-reminders (same pair)\n\nClick OK to run the helper.",
      {
        withTitle: "Reassign overdue reminders",
        buttons: ["Cancel", "OK"],
        defaultButton: "OK",
      }
    );
  } catch (e) {
    log("Canceled or closed start dialog — exiting.");
    return;
  }

  var overdue = getOverdueWorkItems();
  if (overdue === null) {
    var errMsg =
      "The list-reminders helper failed or was not found. Fix the helper (see paths in the first dialog) and try again. This script will not fall back to slow Reminders.app scripting.";
    log(errMsg);
    try {
      sa.displayDialog(errMsg, {
        withTitle: "Reassign overdue reminders",
        buttons: ["OK"],
        defaultButton: "OK",
      });
    } catch (e2) {}
    return;
  }
  notifyUser(
    "Found " +
      overdue.length +
      " overdue (before today). Starting menus…",
    "Reassign overdue reminders"
  );

  var updatedCount = 0;
  var skippedCount = 0;
  var errorCount = 0;

  for (var idx = 0; idx < overdue.length; idx++) {
    var item = overdue[idx];
    var originalDueDate = item.originalDueDate;
    if (!originalDueDate || isNaN(originalDueDate.getTime())) {
      skippedCount++;
      log("Skipping item with missing due date (unexpected).");
      continue;
    }

    var pick = promptForChoice(
      item.title,
      formatDateTime(originalDueDate)
    );
    if (pick.canceled) {
      skippedCount++;
      log("Menu canceled; counting as skip.");
      continue;
    }

    var choice = pick.value;
    if (choice === "Quit") {
      log("User chose Quit; stopping.");
      break;
    }
    if (choice === "Skip") {
      skippedCount++;
      log("Skipped by user.");
      continue;
    }

    var newDue = null;
    if (choice === "Custom") {
      var custom = promptForCustomDate(originalDueDate);
      if (custom.canceled) {
        skippedCount++;
        log("Custom date canceled; counting as skip.");
        continue;
      }
      newDue = custom.date;
    } else {
      var effectiveNow = new Date();
      newDue = computeNewDueDate(choice, originalDueDate, effectiveNow);
    }

    if (!newDue || isNaN(newDue.getTime())) {
      errorCount++;
      log("Could not compute new due date for choice: " + choice);
      continue;
    }

    try {
      updateWorkItemDueDate(item, newDue, DRY_RUN);
      updatedCount++;
    } catch (e) {
      errorCount++;
      log("Error updating \"" + (item.title || "") + "\": " + e);
    }
  }

  var summary =
    "Done. Updated: " +
    updatedCount +
    ", skipped: " +
    skippedCount +
    ", errors: " +
    errorCount +
    (DRY_RUN ? " (DRY_RUN)" : "");
  log(summary);

  try {
    sa.displayDialog(summary, {
      withTitle: "Reassign overdue reminders",
      buttons: ["OK"],
      defaultButton: "OK",
    });
  } catch (e) {
    log("Summary dialog failed (user may have dismissed): " + e);
  }
}

run();
