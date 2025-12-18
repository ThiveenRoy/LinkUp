/* eslint-disable @typescript-eslint/no-explicit-any */

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import * as corsLib from "cors";
import Stripe from "stripe";

admin.initializeApp();
const db = admin.firestore();
/* -------------------------------------------------------------------------- */
/* Shared helpers */
/* -------------------------------------------------------------------------- */

function fmtDate(d: Date, tz: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: tz,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(d);
}

function fmtTime(d: Date, tz: string): string {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });

  const parts = dtf.formatToParts(d);
  const hour = parts.find((p) => p.type === "hour")?.value ?? "";
  const minute = parts.find((p) => p.type === "minute")?.value ?? "";
  const day = (parts.find((p) => p.type === "dayPeriod")?.value ?? "").toLowerCase();

  return `${hour}:${minute} ${day}`;
}

function formatWhen(ev: any, opts?: { tz?: string }): string {
  const tz = opts?.tz || "Asia/Singapore";

  if (ev?.isAllDay) {
    const s = ev.startDate?.toDate?.();
    const e = ev.endDate?.toDate?.();
    if (s && e) {
      const sd = fmtDate(s, tz);
      const ed = fmtDate(e, tz);
      return sd === ed ? `${sd} (all day)` : `${sd} → ${ed} (all day)`;
    }
    if (s) return `${fmtDate(s, tz)} (all day)`;
    return "(all day)";
  }

  const st = ev?.startTime?.toDate?.();
  const et = ev?.endTime?.toDate?.();

  if (st && et) {
    const sd = fmtDate(st, tz);
    const ed = fmtDate(et, tz);
    return sd === ed
      ? `${sd}, ${fmtTime(st, tz)} → ${fmtTime(et, tz)}`
      : `${sd}, ${fmtTime(st, tz)} → ${ed}, ${fmtTime(et, tz)}`;
  }

  if (st) return `${fmtDate(st, tz)}, ${fmtTime(st, tz)}`;
  return "(time TBA)";
}

async function resolveAddedBy(ev: any): Promise<string> {
  if (ev?.creatorName) return ev.creatorName;
  if (!ev?.creatorId) return "someone";
  try {
    const snap = await db.doc(`users/${ev.creatorId}`).get();
    const u = snap.data() || {};
    return u.displayName || u.email || "someone";
  } catch {
    return "someone";
  }
}

/* -------------------------------------------------------------------------- */
/* Firestore Trigger */
/* -------------------------------------------------------------------------- */

export const onEventCreate = onDocumentCreated(
  {
    region: "asia-southeast1",
    document: "calendars/{calId}/events/{eventId}",
    retry: true,
  },
  async (event) => {
    try {
      const ev = event.data?.data();
      if (!ev) return;

      const calId = event.params.calId;
      const calSnap = await db.doc(`calendars/${calId}`).get();
      const cal = calSnap.data();
      if (!cal?.isShared) return;

      const memberIds: string[] = cal.memberIds || [];
      const emails: string[] = [];

      const users = await db.getAll(
        ...memberIds.map((id: string) => db.doc(`users/${id}`))
      );

      users.forEach((u) => {
        const d = u.data();
        if (d?.notif?.emailEnabled && d.email) emails.push(d.email);
      });

      if (!emails.length) return;

      const whenStr = formatWhen(ev, { tz: cal.timeZone });
      const addedBy = await resolveAddedBy(ev);

      const batch = db.batch();

      emails.forEach((to) => {
        batch.set(db.collection("mail_queue").doc(), {
          to,
          calName: cal.name,
          title: ev.title,
          whenStr,
          addedBy,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      await batch.commit();
    } catch (e) {
      logger.error("onEventCreate failed", e);
    }
  }
);

/* -------------------------------------------------------------------------- */
/* Scheduled Digest (BEAUTIFIED EMAIL) */
/* -------------------------------------------------------------------------- */

export const sendDueDigests = onSchedule(
  {
    region: "asia-southeast1",
    schedule: "every 3 minutes",
    timeZone: "UTC",
  },
  async () => {
    const q = await db.collection("mail_queue").orderBy("createdAt").get();
    if (q.empty) return;

    const grouped = new Map<string, any[]>();

    q.docs.forEach((d) => {
      const x = d.data();
      if (!grouped.has(x.to)) grouped.set(x.to, []);
      grouped.get(x.to)!.push({ ...x, id: d.id });
    });

    const batch = db.batch();

    for (const [to, items] of grouped.entries()) {
      const calName = items[0].calName || "your calendar";

      const eventCards = items
        .map(
          (e) => `
<tr>
  <td style="padding:12px;background:#f9fafb;border-radius:10px;">
    <b style="font-size:16px;">📅 ${e.title}</b><br/>
    <span style="color:#374151;">${e.whenStr}</span><br/>
    <span style="color:#6b7280;font-size:13px;">by ${e.addedBy}</span>
  </td>
</tr>
<tr><td style="height:12px"></td></tr>`
        )
        .join("");

      const html = `
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#f6f7fb;font-family:Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0">
<tr>
<td align="center" style="padding:24px">
<table style="max-width:520px;background:#fff;border-radius:14px;padding:24px">
<tr>
<td>
<h2 style="margin:0;color:#3f72af;">🔗 LinkUp Calendar</h2>
<p style="color:#6b7280">New events added to <b>${calName}</b></p>
</td>
</tr>
<tr><td style="height:16px;border-bottom:1px solid #e5e7eb"></td></tr>
<tr><td style="height:16px"></td></tr>
${eventCards}
<tr>
<td style="text-align:center;font-size:12px;color:#9ca3af;padding-top:16px">
You’re receiving this because email notifications are enabled.<br/>
— LinkUp Calendar
</td>
</tr>
</table>
</td>
</tr>
</table>
</body>
</html>`;

      batch.set(db.collection("mail").doc(), {
        to,
        message: {
          subject: `[${calName}] ${items.length} new event(s)`,
          html,
        },
      });

      items.forEach((i) =>
        batch.delete(db.collection("mail_queue").doc(i.id))
      );
    }

    await batch.commit();
  }
);

/* -------------------------------------------------------------------------- */
/* Stripe Configuration */
/* -------------------------------------------------------------------------- */

const STRIPE_SECRET = defineSecret("STRIPE_SECRET");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

const PRICE_MAP: Record<
  string,
  { price: string; mode: "subscription" | "payment" }
> = {
  monthly: { price: "price_1SfZpuKBxi2gbJEpWVVfNrf6", mode: "subscription" },
  yearly: { price: "price_1SfZqMKBxi2gbJEp906ObYct", mode: "subscription" },
};

const cors = corsLib({ origin: true });

async function verifyAuth(req: any): Promise<admin.auth.DecodedIdToken> {
  const auth = req.headers.authorization || "";
  const m = auth.match(/^Bearer (.+)$/i);
  if (!m) throw new Error("Missing Authorization: Bearer <ID_TOKEN>");
  return await admin.auth().verifyIdToken(m[1]);
}

const stripeFromSecret = (sk: string) => new Stripe(sk, { apiVersion: "2025-08-27.basil" });

/* -------------------------------------------------------------------------- */
/* Create Checkout Session */
/* -------------------------------------------------------------------------- */

export const createCheckoutSession = onRequest(
  { region: "asia-southeast1", secrets: [STRIPE_SECRET] },
  async (req, res) => {
    await new Promise<void>((resolve) => {
      cors(req, res, async () => {
        try {
          if (req.method !== "POST") {
            res.status(405).send("Use POST");
            return resolve();
          }

          const decoded = await verifyAuth(req);
          const uid = decoded.uid;

          const { plan, successUrl, cancelUrl } = req.body || {};

          if (!plan || !PRICE_MAP[plan]) {
            res.status(400).json({ error: "Unknown or missing plan" });
            return resolve();
          }

          if (!successUrl || !cancelUrl) {
            res.status(400).json({ error: "Missing success/cancel urls" });
            return resolve();
          }

          const stripe = stripeFromSecret(STRIPE_SECRET.value());
          const userRef = db.collection("users").doc(uid);
          const doc = await userRef.get();

          let customerId = doc.get("stripeCustomerId");

          if (!customerId) {
            const authUser = await admin.auth().getUser(uid).catch(() => null);
            const customer = await stripe.customers.create({
              email: authUser?.email,
              name: authUser?.displayName,
              metadata: { firebaseUid: uid },
            });

            customerId = customer.id;
            await userRef.set({ stripeCustomerId: customerId }, { merge: true });
          }

          const price = PRICE_MAP[plan];

          const session = await stripe.checkout.sessions.create({
            mode: price.mode,
            line_items: [{ price: price.price, quantity: 1 }],
            customer: customerId,
            success_url: successUrl,
            cancel_url: cancelUrl,
            metadata: { firebaseUid: uid, plan },
            billing_address_collection: "auto",
            allow_promotion_codes: true,
          });

          res.json({ url: session.url });
        } catch (e: any) {
          logger.error("createCheckoutSession failed", e);
          res.status(500).json({ error: e.message || "server_error" });
        } finally {
          resolve();
        }
      });
    });
  }
);

/* -------------------------------------------------------------------------- */
/* Stripe Webhook */
/* -------------------------------------------------------------------------- */

export const stripeWebhook = onRequest(
  {
    region: "asia-southeast1",
    secrets: [STRIPE_SECRET, STRIPE_WEBHOOK_SECRET],
  },
  async (req, res): Promise<void> => {
    try {
      const stripe = stripeFromSecret(STRIPE_SECRET.value());
      const sig = req.headers["stripe-signature"];

      if (!sig) {
        res.status(400).send("Missing stripe-signature");
        return;
      }

      let event: Stripe.Event;

      try {
        event = stripe.webhooks.constructEvent(
          req.rawBody,
          sig as string,
          STRIPE_WEBHOOK_SECRET.value()
        );
      } catch (err: any) {
        logger.error("Webhook signature verification failed", err.message);
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
      }

      // -------------------------
      // Handle Stripe Events Here
      // -------------------------
      if (event.type === "checkout.session.completed") {
        const session = event.data.object as Stripe.Checkout.Session;
        const uid = session.metadata?.firebaseUid;
        const plan = session.metadata?.plan;

        if (uid) {
          await db.doc(`users/${uid}`).set(
            {
              premium: true,
              premiumPlan: plan || null,
              premiumSince: admin.firestore.FieldValue.serverTimestamp(),
              showPremiumWelcome: true,
            },
            { merge: true }
          );
        }
      }

      if (event.type === "customer.subscription.updated") {
        const sub = event.data.object as Stripe.Subscription;
        const customerId = sub.customer as string;

        if (customerId) {
          const snap = await db
            .collection("users")
            .where("stripeCustomerId", "==", customerId)
            .limit(1)
            .get();

          if (!snap.empty) {
            const doc = snap.docs[0];
            const userData = doc.data();

            // Keep the previous plan (monthly or yearly)
            const existingPlan = userData.premiumPlan || null;

            const active =
              sub.status === "active" || sub.status === "trialing";

            await doc.ref.set(
              {
                premium: active,
                premiumPlan: existingPlan, // KEEP monthly OR yearly
                subscriptionStatus: sub.status,
              },
              { merge: true }
            );
          }
        }
      }

      // Final OK response
      res.status(200).send("[OK]");
      return;
    } catch (err) {
      logger.error("stripeWebhook handler failed", err);
      res.status(500).send("Webhook handler error");
      return;
    }
  }
);


/* -------------------------------------------------------------------------- */
/* Create Portal Session */
/* -------------------------------------------------------------------------- */

export const createPortalSession = onRequest(
  { region: "asia-southeast1", secrets: [STRIPE_SECRET] },
  async (req, res) => {
    await new Promise<void>((resolve) => {
      cors(req, res, async () => {
        try {
          if (req.method !== "POST") {
            res.status(405).send("Use POST");
            return resolve();
          }

          const decoded = await verifyAuth(req);
          const uid = decoded.uid;

          const { returnUrl } = req.body || {};
          if (!returnUrl) {
            res.status(400).json({ error: "Missing returnUrl" });
            return resolve();
          }

          const userDoc = await db.doc(`users/${uid}`).get();
          const customerId = userDoc.get("stripeCustomerId");

          if (!customerId) {
            res.status(400).json({ error: "No Stripe customer" });
            return resolve();
          }

          const stripe = stripeFromSecret(STRIPE_SECRET.value());
          const portal = await stripe.billingPortal.sessions.create({
            customer: customerId,
            return_url: returnUrl,
          });

          res.json({ url: portal.url });
        } catch (e: any) {
          logger.error("createPortalSession failed", e);
          res.status(500).json({ error: e.message || "server_error" });
        } finally {
          resolve();
        }
      });
    });
  }
);

