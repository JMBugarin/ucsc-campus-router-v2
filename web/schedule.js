"use strict";

// The student's schedule lives in this browser (localStorage). The server only
// checks it and works out walking times; it stores nothing.
(() => {
  const STORE = "ucsc-router-schedule-v1";
  const DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];
  const TIME_ZONE = "America/Los_Angeles";
  const REFRESH_MS = 60 * 1000;
  const POSITION_MAX_AGE_MS = 2 * 60 * 1000;

  const $ = (id) => document.getElementById(id);
  const els = {
    summary: $("today-summary"), walk: $("today-walk"), list: $("today-list"),
    routeNext: $("route-next"), useLocation: $("use-location"),
    paste: $("paste"), importBtn: $("import-btn"), manualForm: $("manual-form"),
    icsFile: $("ics-file"), icsBtn: $("ics-btn"), remindOn: $("remind-on"), remindLead: $("remind-lead"), leaveBanner: $("leave-banner"),
    photoFile: $("photo-file"), photoBtn: $("photo-btn"), photoReason: $("photo-reason"), ocrBtn: $("ocr-btn"),
    message: $("schedule-message"), meetings: $("meeting-list"), clear: $("clear-schedule"),
    once: $("m-once"), days: $("m-days"), from: $("m-from"), to: $("m-to"), toLabel: $("m-to-label"),
  };

  const clock = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: TIME_ZONE });
  const weekday = new Intl.DateTimeFormat("en-US", { weekday: "short", timeZone: TIME_ZONE });

  let meetings = [];
  let locations = [];
  let term = null;
  let position = null; // { point: [lat, lon], at: ms }
  let timer = 0;
  let latest = null; // last /api/today response

  /* ---- small helpers -------------------------------------------------- */

  const fmtTime = (iso) => clock.format(new Date(iso));

  function fmtClock(hhmm) {
    const [h, m] = hhmm.split(":").map(Number);
    return `${h % 12 || 12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
  }

  function fmtDuration(minutes) {
    const total = Math.round(minutes);
    if (total < 1) return "less than a minute";
    if (total < 60) return `${total} min`;
    const h = Math.floor(total / 60), m = total % 60;
    return m ? `${h} h ${m} min` : `${h} h`;
  }

  const label = (occ) => [occ.course, occ.component].filter(Boolean).join(" ");

  function el(tag, props = {}, ...children) {
    const node = Object.assign(document.createElement(tag), props);
    node.append(...children);
    return node;
  }

  function store(list) {
    try { localStorage.setItem(STORE, JSON.stringify(list)); } catch (e) { /* private mode: keep going */ }
  }

  function restore() {
    try { return JSON.parse(localStorage.getItem(STORE)) || []; } catch (e) { return []; }
  }

  async function post(path, body) {
    const res = await fetch(`/api/${path}`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || res.statusText);
    return data;
  }

  function say(text, isError = false) {
    els.message.textContent = text;
    els.message.classList.toggle("error", isError);
  }

  /* ---- the schedule ---------------------------------------------------- */

  async function setSchedule(list) {
    const cleaned = await post("schedule/clean", { meetings: list });
    meetings = cleaned.meetings;
    locations = cleaned.locations;
    store(meetings);
    renderMeetings();
    refreshToday();
  }

  const sameClass = (a, b) =>
    JSON.stringify([a.course, a.component, a.section, a.days, a.start, a.end, a.location, a.start_date]) ===
    JSON.stringify([b.course, b.component, b.section, b.days, b.start, b.end, b.location, b.start_date]);

  function renderMeetings() {
    els.clear.hidden = meetings.length === 0;
    els.meetings.replaceChildren(
      ...meetings.map((m, i) => {
        const loc = locations[i] || {};
        const when = m.days.length
          ? `${m.days.map((d) => DAYS[d]).join("")} ${fmtClock(m.start)}–${fmtClock(m.end)}`
          : `${m.start_date} ${fmtClock(m.start)}–${fmtClock(m.end)}`;
        const where = el("span", { className: "where" }, m.location || "No location");
        const note = { building: loc.building_name, online: "online", tba: "no room yet",
                       unknown: "not recognised, so I can't time the walk" }[loc.kind];
        const remove = el("button", { type: "button", className: "remove", title: "Remove this class", textContent: "×" });
        remove.setAttribute("aria-label", `Remove ${label(m)}`);
        remove.addEventListener("click", () => setSchedule(meetings.filter((_, j) => j !== i)));
        return el("li", { className: loc.kind === "unknown" ? "problem" : "" },
          el("strong", {}, label(m)), ` · ${when} · `, where, note ? el("small", {}, ` (${note})`) : "", remove);
      })
    );
  }

  /* ---- today ----------------------------------------------------------- */

  const WHY = {
    weekend: "No classes on weekends.", holiday: "No classes today (holiday).",
    before_term: "The term hasn't started yet.", after_term: "The term is over.",
    no_schedule: "Add your classes to see what is next.", no_classes: "No classes today.",
  };

  const day = (iso) => weekday.format(new Date(iso));

  function nextText(next) {
    return next.is_today
      ? `${label(next)} at ${fmtTime(next.start)} in ${fmtDuration(next.starts_in_min)}`
      : `${day(next.start)} ${fmtTime(next.start)}, ${label(next)}`;
  }

  function chip(status, text) {
    return el("span", { className: `chip ${status}` }, text);
  }

  function spareText(freeMin, leaveBy) {
    if (freeMin < 0) return ["late", `Not enough time: you'd arrive about ${fmtDuration(-freeMin)} late.`];
    const leave = leaveBy ? ` Leave by ${fmtTime(leaveBy)}.` : "";
    if (freeMin < 5) return ["tight", `Tight: only ${fmtDuration(freeMin)} to spare.${leave}`];
    return ["ok", `${fmtDuration(freeMin)} of free time.${leave}`];
  }

  function renderToday(d) {
    latest = d;
    els.walk.hidden = true;
    els.walk.replaceChildren();
    els.list.replaceChildren();
    els.routeNext.disabled = !(d && d.next && d.next.location);
    if (!d) {
      els.summary.textContent = WHY.no_schedule;
      return;
    }

    const next = d.next;
    if (d.state === "in_class") {
      els.summary.textContent = `In ${label(d.current)} until ${fmtTime(d.current.end)} (${fmtDuration(d.current.minutes_left)} left).` +
        (next ? ` Next: ${nextText(next)}.` : "");
    } else if (d.state === "before_classes" || d.state === "between_classes") {
      els.summary.textContent = `Next: ${nextText(next)}.`;
    } else if (d.state === "done_for_today") {
      els.summary.textContent = "Done for today." + (next ? ` Next class: ${nextText(next)}.` : "");
    } else {
      els.summary.textContent = (WHY[d.reason] || WHY.no_classes) + (next ? ` Next class: ${nextText(next)}.` : "");
    }

    if (next && d.walk) {
      const from = { here: "your location", current_class: "your current class", previous_class: "your last class" }[d.walk.from];
      const [status, text] = spareText(d.free_min, d.leave_by);
      els.walk.hidden = false;
      els.walk.append(chip(status, status === "ok" ? "OK" : status === "tight" ? "Tight" : "Late"),
        ` Walk to ${next.location} is about ${d.walk.minutes} min from ${from}. ${text}`);
    } else if (next && d.notes.length) {
      els.walk.hidden = false;
      els.walk.textContent = d.notes.join(" ");
    } else if (d.notes.length) {
      els.walk.hidden = false;
      els.walk.textContent = d.notes.join(" ");
    }
    if (next && d.walk && d.notes.length) els.walk.append(` ${d.notes.join(" ")}`);

    els.list.append(...d.today.map((t) => {
      const isNow = d.current && d.current.start === t.start;
      const isNext = next && next.start === t.start && next.is_today;
      const li = el("li", { className: isNow ? "now" : isNext ? "next" : "" },
        el("span", { className: "when" }, `${fmtTime(t.start)}–${fmtTime(t.end)}`), ` ${label(t)} · ${t.location}`);
      if (t.gap_min !== undefined) {
        const gap = el("div", { className: "gap" });
        if (t.walk_min !== undefined) {
          const [status, text] = spareText(t.free_min);
          gap.append(chip(status, status === "ok" ? "OK" : status === "tight" ? "Tight" : "Late"),
            ` ${fmtDuration(t.gap_min)} between classes, ${t.walk_min} min walk. ${text}`);
        } else {
          gap.textContent = `${fmtDuration(t.gap_min)} between classes (can't time the walk).`;
        }
        li.prepend(gap);
      }
      return li;
    }));
  }

  async function currentPosition() {
    if (position && Date.now() - position.at < POSITION_MAX_AGE_MS) return position.point;
    if (!navigator.geolocation) return null;
    return new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (p) => {
          position = { point: [p.coords.latitude, p.coords.longitude], at: Date.now() };
          resolve(position.point);
        },
        () => {
          els.useLocation.checked = false;
          say("Couldn't get your location, so walking times start from your last class instead.", true);
          resolve(null);
        },
        { enableHighAccuracy: true, timeout: 10000, maximumAge: POSITION_MAX_AGE_MS }
      );
    });
  }

  async function refreshToday() {
    clearTimeout(timer);
    if (!meetings.length) {
      renderToday(null);
      afterToday();
      return;
    }
    const body = { meetings, remind_lead: Number(els.remindLead.value), reminded: sentReminders() };
    if (els.useLocation.checked) {
      const here = await currentPosition();
      if (here) body.here = here;
    }
    try {
      renderToday(await post("today", body));
      afterToday();
    } catch (err) {
      els.summary.textContent = err.message;
    }
    timer = setTimeout(refreshToday, REFRESH_MS);
  }

  /* ---- leave-now reminders ---------------------------------------------- */

  // The server works out what to show and when (timetable.plan_reminders); this page only arms
  // timers and shows the notifications. They are browser notifications, so they only fire while
  // this page is open.
  const REMIND_KEY = `${STORE}-remind`;
  const SENT_KEY = `${STORE}-reminded`;
  const MAX_TIMER_MS = 6 * 60 * 60 * 1000;
  let reminderTimers = [];

  function loadReminderSettings() {
    try { return JSON.parse(localStorage.getItem(REMIND_KEY)) || {}; } catch (e) { return {}; }
  }

  function saveReminderSettings() {
    try {
      localStorage.setItem(REMIND_KEY, JSON.stringify({ on: els.remindOn.checked, lead: Number(els.remindLead.value) }));
    } catch (e) { /* private mode: the settings just aren't remembered */ }
  }

  function sentReminders() {
    try { return JSON.parse(localStorage.getItem(SENT_KEY)) || []; } catch (e) { return []; }
  }

  function markSent(key) {
    try {
      localStorage.setItem(SENT_KEY, JSON.stringify([...new Set([...sentReminders(), key])].slice(-40)));
    } catch (e) { /* ignore */ }
  }

  function showReminder(item) {
    if (sentReminders().includes(item.key)) return;
    markSent(item.key);
    try {
      const note = new Notification(item.title, { body: item.body, tag: item.key });
      note.onclick = () => { window.focus(); note.close(); };
    } catch (e) { /* the banner on the page still shows */ }
  }

  function afterToday() {
    const d = latest;
    // a banner on the page itself when it is nearly time to leave, whether or not notifications are on
    els.leaveBanner.hidden = !(d && d.banner);
    if (d && d.banner) {
      els.leaveBanner.textContent = d.banner.text;
      els.leaveBanner.classList.toggle("late", d.banner.late);
    }
    reminderTimers.forEach(clearTimeout);
    reminderTimers = [];
    if (!els.remindOn.checked || !d || !d.reminders) return;
    for (const item of d.reminders) {
      const delay = Math.round(item.in_seconds * 1000);
      if (delay <= MAX_TIMER_MS) reminderTimers.push(setTimeout(() => showReminder(item), delay));
    }
  }

  els.remindOn.addEventListener("change", async () => {
    if (els.remindOn.checked) {
      if (!("Notification" in window)) {
        els.remindOn.checked = false;
        say("This browser can't show notifications, so I can only show the banner on this page.", true);
      } else {
        const permission = Notification.permission === "default" ? await Notification.requestPermission() : Notification.permission;
        if (permission !== "granted") {
          els.remindOn.checked = false;
          say("Notifications are blocked for this page. Allow them in your browser's site settings to get reminders.", true);
        }
      }
    }
    saveReminderSettings();
    refreshToday();  // the plan depends on the setting, so ask the server again
  });

  els.remindLead.addEventListener("change", () => {
    saveReminderSettings();
    refreshToday();
  });

  /* ---- importing and adding -------------------------------------------- */

  // Add what an import found, skipping classes already in the schedule. Returns how many were new.
  async function addImported(parsed, hint = "") {
    const fresh = parsed.meetings.filter((m) => !meetings.some((old) => sameClass(old, m)));
    await setSchedule([...meetings, ...fresh]);
    const skipped = parsed.meetings.length - fresh.length;
    say([`Added ${fresh.length} class${fresh.length === 1 ? "" : "es"}` + (skipped ? ` (${skipped} already there)` : "") + ".",
         ...parsed.notes, fresh.length ? hint : ""].filter(Boolean).join(" "),
        fresh.length === 0 && parsed.notes.length > 0);
    return fresh.length;
  }

  els.importBtn.addEventListener("click", async () => {
    const text = els.paste.value;
    if (!text.trim()) return say("Paste your schedule first.", true);
    try {
      // calendar text pasted into the box is recognised and read as a calendar
      const route = /BEGIN:VCALENDAR/i.test(text) ? "schedule/ics" : "schedule/parse";
      if (await addImported(await post(route, { text }))) els.paste.value = "";
    } catch (err) {
      say(err.message, true);
    }
  });

  /* ---- calendar file (.ics) ---------------------------------------------- */

  els.icsFile.addEventListener("change", () => { els.icsBtn.disabled = els.icsFile.files.length === 0; });

  els.icsBtn.addEventListener("click", async () => {
    const file = els.icsFile.files[0];
    if (!file) return;
    els.icsBtn.disabled = true;
    try {
      if (file.size > 1_000_000) throw new Error("That file is too large to be a class calendar.");
      const found = await post("schedule/ics", { text: await file.text() });
      if (await addImported(found, "Check the classes, and remove any that aren't yours.")) els.icsFile.value = "";
    } catch (err) {
      say(err.message, true);
    } finally {
      els.icsBtn.disabled = els.icsFile.files.length === 0;
    }
  });

  /* ---- reading a photo -------------------------------------------------- */

  const MAX_EDGE_PX = 2000;

  // Shrink and re-encode as JPEG in the browser: smaller to send, under the 5 MB limit,
  // and it drops metadata such as where the photo was taken.
  async function prepareImage(file) {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, MAX_EDGE_PX / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.88));
    if (!blob) throw new Error("Couldn't prepare that image.");
    const data = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result).split(",")[1]);
      reader.onerror = () => reject(new Error("Couldn't read that image."));
      reader.readAsDataURL(blob);
    });
    return { image: data, media_type: "image/jpeg" };
  }

  /* ---- reading on this device (no account, nothing uploaded) ------------ */

  // The text reader (Tesseract.js) is loaded only when asked for, and the browser checks the
  // file against this hash before running it.
  const TESSERACT_URL = "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js";
  const TESSERACT_SRI = "sha384-GJqSu7vueQ9qN0E9yLPb3Wtpd7OrgK8KmYzC8T1IysG1bcvxvIO4qtYR/D3A991F";
  const TARGET_TEXT_PX = 28;   // text about this tall reads best
  const MAX_SCALE = 4;
  const MAX_SIDE_PX = 6000;    // keeps the enlarged picture within what a browser can handle
  const MEASURE_SIDE_PX = 2000;
  let tesseractLoading = null;

  function loadTesseract() {
    if (window.Tesseract) return Promise.resolve();
    tesseractLoading ??= new Promise((resolve, reject) => {
      const tag = el("script", { src: TESSERACT_URL, integrity: TESSERACT_SRI, crossOrigin: "anonymous" });
      tag.onload = resolve;
      tag.onerror = () => {
        tesseractLoading = null;
        reject(new Error("Couldn't load the text reader. Check your internet connection and try again."));
      };
      document.head.append(tag);
    });
    return tesseractLoading;
  }

  function drawScaled(bitmap, scale) {
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const g = canvas.getContext("2d");
    g.imageSmoothingQuality = "high";
    g.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  const median = (list) => [...list].sort((a, b) => a - b)[Math.floor(list.length / 2)];

  // Opens the picture, measures its text, and returns a reader that can recognise it at any
  // enlargement. Small text reads poorly, and results vary a little with the size, so the caller
  // may read the same picture more than once.
  async function openReader(file) {
    say("Loading the text reader (the first time takes a little while)…");
    await loadTesseract();
    const bitmap = await createImageBitmap(file);
    const longest = Math.max(bitmap.width, bitmap.height);
    const worker = await Tesseract.createWorker("eng");
    try {
      await worker.setParameters({ tessedit_pageseg_mode: "11" }); // sparse text suits table cells
      const toWords = (data, scale) => ({
        text: data.text,
        words: data.words.map((w) => ({ text: w.text, x0: Math.round(w.bbox.x0 / scale), y0: Math.round(w.bbox.y0 / scale),
                                        x1: Math.round(w.bbox.x1 / scale), y1: Math.round(w.bbox.y1 / scale) })),
      });
      const readAt = async (scale) => toWords((await worker.recognize(drawScaled(bitmap, scale))).data, scale);

      say("Measuring the text…");
      const firstScale = Math.min(1, MEASURE_SIDE_PX / longest);
      const first = (await worker.recognize(drawScaled(bitmap, firstScale))).data;
      const heights = first.words.filter((w) => /[A-Za-z0-9]/.test(w.text)).map((w) => (w.bbox.y1 - w.bbox.y0) / firstScale);
      if (heights.length < 5) throw new Error("I couldn't find any text in that picture.");
      const clamp = (s) => Math.max(1, Math.min(MAX_SCALE, MAX_SIDE_PX / longest, s));
      const base = clamp(TARGET_TEXT_PX / median(heights));
      return {
        // enlargements to try, best guess first: a bit smaller and a bit larger give different readings
        scales: [...new Set([base, base * 0.75, base * 1.3].map((s) => Math.round(clamp(s) * 20) / 20))],
        firstScale, first: toWords(first, firstScale), readAt,
        close: () => worker.terminate(),
      };
    } catch (err) {
      await worker.terminate();
      throw err;
    }
  }

  const classKey = (m) => JSON.stringify([m.course, m.component, m.days, m.location]);
  const unreadable = (found) => found.notes.some((n) => /^Couldn't read|^No classes/.test(n));

  // Combine two readings of the same picture. Where both found a class, the earlier reading wins,
  // so a class is never listed twice with different times.
  function combine(a, b) {
    const seen = new Set(a.meetings.map(classKey));
    const notes = [...new Set([...a.notes.filter((n) => !/^Couldn't read|^No classes/.test(n)), ...b.notes])];
    return { ...b, meetings: [...a.meetings, ...b.meetings.filter((m) => !seen.has(classKey(m)))], notes };
  }

  els.ocrBtn.addEventListener("click", async () => {
    const file = els.photoFile.files[0];
    if (!file) return;
    els.ocrBtn.disabled = true;
    let reader = null, plainText = "", best = null, lastError = null;
    try {
      reader = await openReader(file);
      for (let i = 0; i < reader.scales.length; i++) {
        say(i === 0 ? "Reading the text. This takes about ten seconds…"
                    : "Some rows were hard to read, so I'm trying again at a different size…");
        const scale = reader.scales[i];
        const read = Math.abs(scale - reader.firstScale) < 0.1 ? reader.first : await reader.readAt(scale);
        plainText = plainText || read.text;
        try {
          const found = await post("schedule/ocr", { words: read.words });
          best = best ? combine(best, found) : found;
          if (!unreadable(found)) break;
        } catch (err) {
          lastError = err;
        }
      }
      if (!best) throw lastError || new Error("I couldn't read a schedule from that picture.");

      say("Rebuilding your schedule…");
      const added = await addImported(best, "Check each class against your picture, and remove or fix any that are wrong.");
      if (added) els.photoFile.value = "";
      // anything still unread: show the rebuilt text so it can be corrected and imported by hand
      if (!added || unreadable(best)) {
        els.paste.value = best.text;
        $("import").open = true;
      }
    } catch (err) {
      say(err.message, true);
      if (plainText) {  // the table couldn't be rebuilt: offer the raw text to tidy by hand
        els.paste.value = plainText;
        $("import").open = true;
      }
    } finally {
      if (reader) await reader.close();
      updatePhotoButton();
    }
  });

  let photoReady = false;

  function updatePhotoButton() {
    const chosen = els.photoFile.files.length > 0;
    els.ocrBtn.disabled = !chosen;
    els.photoBtn.disabled = !(photoReady && chosen);
  }

  async function checkPhotoSupport() {
    try {
      const caps = await fetch("/api/capabilities").then((r) => r.json());
      photoReady = caps.photo.ready;
      els.photoReason.hidden = photoReady;
      els.photoReason.textContent = photoReady ? "" : `Not set up on this server. ${caps.photo.reason}`;
    } catch (e) {
      photoReady = false;
    }
    updatePhotoButton();
  }

  els.photoFile.addEventListener("change", updatePhotoButton);

  els.photoBtn.addEventListener("click", async () => {
    const file = els.photoFile.files[0];
    if (!file) return;
    els.photoBtn.disabled = true;
    say("Reading your photo. This takes a few seconds…");
    try {
      const found = await post("schedule/photo", await prepareImage(file));
      if (await addImported(found, "Check each class against your photo, and remove any that are wrong.")) {
        els.photoFile.value = "";
      }
    } catch (err) {
      say(err.message, true);
    } finally {
      updatePhotoButton();
    }
  });

  els.once.addEventListener("change", () => {
    const once = els.once.checked;
    els.days.hidden = once;
    els.toLabel.hidden = once;
    els.to.required = !once;
    els.from.previousSibling.textContent = once ? "Date " : "From ";
  });

  els.manualForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const once = els.once.checked;
    const days = once ? [] : [...els.days.querySelectorAll("input:checked")].map((c) => Number(c.value));
    if (!once && days.length === 0) return say("Pick the days this class meets.", true);
    const added = {
      course: $("m-course").value, component: $("m-component").value, location: $("m-location").value,
      days, start: $("m-start").value, end: $("m-end").value,
      start_date: els.from.value, end_date: once ? els.from.value : els.to.value,
    };
    try {
      await setSchedule([...meetings, added]);
      say(`Added ${added.course}.`);
      for (const id of ["m-course", "m-location", "m-start", "m-end"]) $(id).value = "";
    } catch (err) {
      say(err.message, true);
    }
  });

  els.clear.addEventListener("click", () => {
    if (confirm("Remove all classes from this browser?")) setSchedule([]);
  });

  els.useLocation.addEventListener("change", () => {
    try { localStorage.setItem(`${STORE}-location`, els.useLocation.checked ? "1" : ""); } catch (e) { /* ignore */ }
    refreshToday();
  });

  els.routeNext.addEventListener("click", () => {
    if (!latest || !latest.next) return;
    $("from-room").value = "";
    $("to-room").value = latest.next.location;
    $("lookup").requestSubmit();
    document.querySelector("main").scrollIntoView({ behavior: "smooth" });
  });

  /* ---- start up ---------------------------------------------------------- */

  async function init() {
    const reminders = loadReminderSettings();
    els.remindLead.value = String(reminders.lead ?? 5);
    els.remindOn.checked = Boolean(reminders.on) && "Notification" in window && Notification.permission === "granted";
    try {
      els.useLocation.checked = Boolean(localStorage.getItem(`${STORE}-location`));
    } catch (e) { /* ignore */ }
    try {
      const [meta, rooms] = await Promise.all([
        fetch("/api/meta").then((r) => r.json()), fetch("/api/rooms").then((r) => r.json())]);
      term = meta.term;
      $("room-names").replaceChildren(...rooms.rooms.map((name) => el("option", { value: name })));
      if (term) { els.from.value = term.start; els.to.value = term.end; }
    } catch (e) {
      say("Could not reach the server. Is server/server.py running?", true);
      return;
    }
    const saved = restore();
    if (!saved.length) return renderMeetings();
    try {
      await setSchedule(saved);
    } catch (err) {
      say(`Your saved schedule couldn't be read (${err.message}), so I cleared it.`, true);
      store([]);
    }
  }

  checkPhotoSupport();
  init();
})();
