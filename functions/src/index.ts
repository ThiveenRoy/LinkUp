/* eslint-disable @typescript-eslint/no-explicit-any */

import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";

admin.initializeApp();
const db = admin.firestore();

/**
 * Format a date in dd/mm/yyyy for a target time zone.
 * @param {Date} d JS Date to format.
 * @param {string} tz IANA time zone
 *   (e.g. "Asia/Singapore").
 * @return {string} dd/mm/yyyy string.
 */
function fmtDate(d: Date, tz: string): string {
  const f = new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  });
  return f.format(d);
}

/**
 * Format a time in h:mm am/pm for a target time zone.
 * @param {Date} d JS Date to format.
 * @param {string} tz IANA time zone.
 * @return {string} time string.
 */
function fmtTime(d: Date, tz: string): string {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour: "2-digit", // ensures 12:00 (not 0:00)
    minute: "2-digit",
    hour12: true,
  });

  const parts = dtf.formatToParts(d);
  const hour = parts.find((p) => p.type === "hour")?.value ?? "";
  const minute = parts.find((p) => p.type === "minute")?.value ?? "";
  const day = (
    parts.find((p) => p.type === "dayPeriod")?.value ?? ""
  ).toLowerCase(); // "am" / "pm"

  return `${hour}:${minute} ${day}`;
}


/**
 * Format an event window (all-day and timed).
 * Uses dd/mm/yyyy and 12-hour times.
 * @param {*} ev Event Firestore data.
 * @param {Object=} opts Optional settings.
 * @param {string=} opts.tz IANA time zone to render in.
 * @return {string} Human-readable time string.
 */
function formatWhen(
  ev: any,
  opts?: { tz?: string }
): string {
  const tz = opts?.tz || "Asia/Singapore";

  // ----- All-day -----
  if (ev?.isAllDay) {
    // support startDate/endDate or startTime/endTime
    const sRaw = ev.startDate ?? ev.startTime;
    const eRaw = ev.endDate ?? ev.endTime;

    const s: Date | null =
      sRaw?.toDate?.() ?? (sRaw ? new Date(sRaw) : null);
    const e: Date | null =
      eRaw?.toDate?.() ?? (eRaw ? new Date(eRaw) : null);

    if (s && e) {
      const sd = fmtDate(s, tz);
      const ed = fmtDate(e, tz);
      // if backend stored end as same-day 23:59:59, this still
      // prints two dates; UX prefers explicit range for clarity.
      if (sd === ed) return `${sd} (all day)`;
      return `${sd} → ${ed} (all day)`;
    }
    if (s) return `${fmtDate(s, tz)} (all day)`;
    return "(all day)";
  }

  // ----- Timed -----
  const stRaw = ev?.startTime;
  const etRaw = ev?.endTime;

  const st: Date | null =
    stRaw?.toDate?.() ?? (stRaw ? new Date(stRaw) : null);
  const et: Date | null =
    etRaw?.toDate?.() ?? (etRaw ? new Date(etRaw) : null);

  if (st && et) {
    const sd = fmtDate(st, tz);
    const ed = fmtDate(et, tz);
    const stStr = fmtTime(st, tz);
    const etStr = fmtTime(et, tz);
    if (sd === ed) {
      return `${sd}, ${stStr} → ${etStr}`;
    }
    return `${sd}, ${stStr} → ${ed}, ${etStr}`;
  }
  if (st) return `${fmtDate(st, tz)}, ${fmtTime(st, tz)}`;
  return "(time TBA)";
}

/**
 * Owner UID from calendar (string or {id}).
 * @param {*} cal Calendar data.
 * @return {string|null} UID or null.
 */
function ownerIdOf(cal: any): string | null {
  if (!cal || cal.owner == null) return null;
  if (typeof cal.owner === "string") return cal.owner;
  if (typeof cal.owner === "object" &&
      typeof cal.owner.id === "string") {
    return cal.owner.id;
  }
  return null;
}

/**
 * Collect member UIDs/emails from calendar.
 * Supports: memberIds, members[{id,email}],
 * invitedEmails.
 * @param {*} cal Calendar data.
 * @return {{uids:string[], directEmails:string[]}}
 */
function extractMembers(
  cal: any
): { uids: string[]; directEmails: string[] } {
  const uids = new Set<string>();
  const directEmails: string[] = [];

  if (Array.isArray(cal?.memberIds)) {
    cal.memberIds.forEach((x: any) => {
      if (typeof x === "string" && x) uids.add(x);
    });
  }

  if (Array.isArray(cal?.members)) {
    cal.members.forEach((m: any) => {
      if (m && typeof m === "object") {
        if (typeof m.id === "string" && m.id) {
          uids.add(m.id);
        }
        if (typeof m.email === "string" && m.email) {
          directEmails.push(m.email);
        }
      }
    });
  }

  if (Array.isArray(cal?.invitedEmails)) {
    cal.invitedEmails.forEach((em: any) => {
      if (typeof em === "string" && em) {
        directEmails.push(em);
      }
    });
  }

  return {uids: Array.from(uids), directEmails};
}

/**
 * Emails for UIDs where notif.emailEnabled==true.
 * @param {string[]} uids User IDs.
 * @return {Promise<string[]>} Emails.
 */
async function lookupEmailsForUids(
  uids: string[]
): Promise<string[]> {
  if (!uids.length) return [];
  const refs = uids.map((id) => db.doc(`users/${id}`));
  const snaps = await db.getAll(...refs);

  const emails: string[] = [];
  for (const s of snaps) {
    const u = s.data() || {};
    const enabled = !!u?.notif?.emailEnabled;
    const email = u?.email as string | undefined;
    if (enabled && email) emails.push(email);
  }
  return emails;
}

/**
 * Friendly "added by" from event or users/{uid}.
 * @param {*} ev Event data.
 * @return {Promise<string>} Name/email/someone.
 */
async function resolveAddedBy(ev: any): Promise<string> {
  const byName = (ev?.creatorName as string) || "";
  if (byName.trim()) return byName.trim();

  const uid = ev?.creatorId as string | undefined;
  if (!uid) return "someone";

  try {
    const doc = await db.doc(`users/${uid}`).get();
    const u = doc.data() || {};
    const dn = (u.displayName as string) || "";
    const em = (u.email as string) || "";
    if (dn.trim()) return dn.trim();
    if (em.trim()) return em.trim();
  } catch {
    // ignore
  }
  return "someone";
}

/**
 * Queue one mail_queue row per recipient on
 * calendars/{calId}/events/{eventId}.
 */
export const onEventCreate = onDocumentCreated(
  {
    region: "asia-southeast1",
    document: "calendars/{calId}/events/{eventId}",
    retry: true,
  },
  async (event) => {
    try {
      const snap = event.data;
      if (!snap) {
        logger.warn("No snapshot in event");
        return;
      }
      const ev = snap.data();
      const calId = event.params?.calId as string;

      const calSnap = await db.doc(
        `calendars/${calId}`
      ).get();
      const cal = calSnap.data() || {};

      // Skip master calendars (not shared).
      if (!cal?.isShared) {
        logger.info("Skip master calendar", {calId});
        return;
      }

      const ownerId = ownerIdOf(cal);
      const extracted = extractMembers(cal);

      const uids = extracted.uids.slice();
      if (ownerId) uids.push(ownerId);

      const uniqueUids = Array.from(new Set(uids));
      const userEmails = await lookupEmailsForUids(
        uniqueUids
      );

      const to = Array.from(new Set([
        ...userEmails,
        ...extracted.directEmails,
      ]));

      if (!to.length) {
        logger.warn("No recipients; skip queue", {
          calId,
        });
        return;
      }

      const tz = (cal?.timeZone as string) ||
        "Asia/Singapore";
      const whenStr = formatWhen(ev, {tz});
      const calName = (cal?.name as string) ||
        "your calendar";
      const title = (ev?.title as string) || "New event";
      const notes = (ev?.description as string) || "";
      const addedBy = await resolveAddedBy(ev);

      const createdAt = admin.firestore
        .FieldValue.serverTimestamp();

      const batch = db.batch();
      to.forEach((email) => {
        const ref = db.collection("mail_queue").doc();
        batch.set(ref, {
          to: email,
          calId,
          calName,
          title,
          whenStr,
          notes,
          addedBy,
          createdAt,
        });
      });
      await batch.commit();

      logger.info("Queued notifications", {
        calId,
        eventId: snap.id,
        toCount: to.length,
      });
    } catch (err: any) {
      logger.error("onEventCreate failed", {
        err: err?.message,
        stack: err?.stack,
      });
      throw err;
    }
  }
);

/**
 * Every 3 minutes, group queued rows by recipient,
 * send one email via /mail, then delete rows.
 */
export const sendDueDigests = onSchedule(
  {
    region: "asia-southeast1",
    schedule: "every 3 minutes",
    timeZone: "UTC",
    retryCount: 0,
  },
  async () => {
    const qSnap = await db.collection(
      "mail_queue"
    ).orderBy("createdAt", "asc").get();

    if (qSnap.empty) return;

    type Row = {
      id: string;
      to: string;
      calName: string;
      title: string;
      whenStr: string;
      notes: string;
      addedBy: string;
    };

    const rows: Row[] = [];
    qSnap.forEach((d) => {
      const x = d.data();
      rows.push({
        id: d.id,
        to: String(x.to),
        calName: String(x.calName || ""),
        title: String(x.title || ""),
        whenStr: String(x.whenStr || ""),
        notes: String(x.notes || ""),
        addedBy: String(x.addedBy || "someone"),
      });
    });

    // group by recipient
    const byTo = new Map<string, Row[]>();
    rows.forEach((r) => {
      const arr = byTo.get(r.to) || [];
      arr.push(r);
      byTo.set(r.to, arr);
    });

    const batch = db.batch();

    for (const [to, list] of byTo.entries()) {
      const first = list[0];
      const calName = first.calName || "your calendar";
      const subject =
        `[${calName}] ${list.length} new event(s)`;

      const partsText: string[] = [];
      const partsHtml: string[] = [];

      list.forEach((r) => {
        partsText.push(
          `• ${r.title} — ${r.whenStr} (by ${r.addedBy})`
        );
        if (r.notes) partsText.push(`  Notes: ${r.notes}`);
        // blank line between items
        partsText.push("");

        const notesHtml = r.notes ?
          `<br/><i>Notes:</i> ${r.notes}` :
          "";
        partsHtml.push(
          "<li style=\"margin:0 0 10px 0;\">" +
          `<b>${r.title}</b> — ${r.whenStr} ` +
          `<i>(by ${r.addedBy})</i>` +
          `${notesHtml}</li>`
        );
      });

      const text =
        `New events in "${calName}":\n\n` +
        partsText.join("\n") +
        "\n— LinkUp Calendar";

      const html =
        `<p>New events in <b>${calName}</b>:</p>` +
        "<ul style=\"padding-left:16px;line-height:1.45;\">" +
        partsHtml.join("") +
        "</ul><p>— LinkUp Calendar</p>";

      const mailRef = db.collection("mail").doc();
      batch.set(mailRef, {
        to,
        message: {subject, text, html},
      });

      list.forEach((r) => {
        const ref = db.collection("mail_queue").doc(r.id);
        batch.delete(ref);
      });
    }

    await batch.commit();
  }
);
