const crypto = require("node:crypto");
const {createGooglePlayClient, createGooglePlayVerifier} = require("./google_play");

const PLANS = Object.freeze({pro: 7500, gold: 15000});
const PAYMENT_UNAVAILABLE = "Purchases are temporarily unavailable. Please try again later.";

// Paymob signs these transaction values, in this order, using HMAC-SHA512.
// https://github.com/PaymobAccept/Paymob-AI-Integration-Skill/blob/main/skills/paymob-integration/references/hmac-verification.md
const SIGNED_FIELDS = [
  "amount_cents", "created_at", "currency", "error_occured",
  "has_parent_transaction", "id", "integration_id", "is_3d_secure",
  "is_auth", "is_capture", "is_refunded", "is_standalone_payment",
  "is_voided", "order.id", "owner", "pending", "source_data.pan",
  "source_data.sub_type", "source_data.type", "success",
];

const validId = value => Number.isSafeInteger(value) && value > 0;
const validPlan = plan => typeof plan === "string" && Object.prototype.hasOwnProperty.call(PLANS, plan);

const validSignature = (transaction, supplied, secret) => {
  if (typeof supplied !== "string" || !/^[a-f\d]{128}$/i.test(supplied) || !secret) return false;
  const values = SIGNED_FIELDS.map(field => field.split(".").reduce(
      (value, key) => value && typeof value === "object" ? value[key] : undefined, transaction));
  if (values.some(value => value === undefined || (value !== null && typeof value === "object"))) return false;
  const expected = crypto.createHmac("sha512", secret).update(values.map(String).join("")).digest();
  return crypto.timingSafeEqual(expected, Buffer.from(supplied, "hex"));
};

// Kept injectable so tests exercise real verification and transactions without a
// merchant account, network calls, credentials or real payments.
exports.createPaymentHandlers = ({onCall, onRequest, HttpsError, admin, axios, env = process.env, googlePlayClient}) => {
  // A disabled billing rollout must not require nonexistent merchant secrets.
  // Set PAYMOB_ENABLED=true and redeploy to bind real secrets when billing is ready.
  const paymobEnabled = env.PAYMOB_ENABLED === "true";
  const secrets = paymobEnabled ? ["PAYMOB_SECRET_KEY", "PAYMOB_HMAC_SECRET"] : [];
  const config = () => {
    const integrationIds = (env.PAYMOB_INTEGRATION_IDS || "").split(",").map(value => Number(value.trim()));
    const mode = env.PAYMOB_MODE;
    const secretKey = env.PAYMOB_SECRET_KEY || "";
    const publicKey = env.PAYMOB_PUBLIC_KEY || "";
    const ready = env.PAYMOB_ENABLED === "true" && ["test", "live"].includes(mode) &&
      secretKey.startsWith(`sk_${mode}_`) && publicKey.startsWith(`pk_${mode}_`) &&
      Boolean(env.PAYMOB_HMAC_SECRET) && integrationIds.length > 0 && integrationIds.every(validId);
    return {ready, integrationIds, secretKey, publicKey};
  };

  const requireAuth = request => {
    if (!request.auth || !request.auth.uid) throw new HttpsError("unauthenticated", "Please sign in before purchasing.");
    return request.auth.uid;
  };

  const getPaymentCapabilities = onCall({secrets}, async request => {
    requireAuth(request);
    const source = request.data ? request.data.source : undefined;
    // Older Android builds did not send a source. New builds explicitly identify
    // the store so enabling Google Play never opens unverified Apple checkout.
    return {paymob: config().ready, nativeStore: env.GOOGLE_PLAY_ENABLED === "true" &&
      (source === undefined || source === "google_play")};
  });

  const verifyGooglePlay = createGooglePlayVerifier({admin, HttpsError,
    client: googlePlayClient || createGooglePlayClient()});
  const verifyStorePurchase = onCall({timeoutSeconds: 60, memory: "256MiB"}, async request => {
    requireAuth(request);
    if (env.GOOGLE_PLAY_ENABLED !== "true") throw new HttpsError("failed-precondition", PAYMENT_UNAVAILABLE);
    return verifyGooglePlay(request);
  });

  const createPaymobOrder = onCall({timeoutSeconds: 60, memory: "256MiB", secrets}, async request => {
    const uid = requireAuth(request);
    const data = request.data || {};
    if (data.userId !== undefined && data.userId !== uid) {
      throw new HttpsError("permission-denied", "A purchase must belong to the signed-in account.");
    }
    if (!validPlan(data.planType)) throw new HttpsError("invalid-argument", "Choose a valid plan.");
    const settings = config();
    if (!settings.ready) throw new HttpsError("failed-precondition", PAYMENT_UNAVAILABLE);
    const user = await admin.firestore().collection("users").doc(uid).get();
    if (!user.exists) throw new HttpsError("failed-precondition", "Complete your profile before purchasing.");
    const email = request.auth.token && request.auth.token.email;
    if (typeof email !== "string" || !email.includes("@")) {
      throw new HttpsError("failed-precondition", "Add an email address to your account before purchasing.");
    }
    const amountCents = PLANS[data.planType];
    try {
      const response = await axios.post("https://accept.paymob.com/v1/intention/", {
        amount: amountCents,
        currency: "EGP",
        payment_methods: settings.integrationIds,
        special_reference: crypto.randomUUID(),
        expiration: 3600,
        billing_data: {
          first_name: user.data().displayName || "Na2slna",
          last_name: "User", email, phone_number: "NA",
          apartment: "NA", floor: "NA", building: "NA", street: "NA",
          country: "EG", city: "NA", state: "NA",
        },
      }, {
        headers: {"Authorization": `Token ${settings.secretKey}`, "Content-Type": "application/json"},
        timeout: 15000,
      });
      const result = response.data || {};
      if (!validId(result.intention_order_id) || typeof result.client_secret !== "string" || !result.client_secret) {
        throw new Error("Invalid payment provider response");
      }
      // Persist the provider's order ID before returning a checkout secret.
      // Webhooks trust this server-only record, never unsigned extras/metadata.
      await admin.firestore().collection("paymentOrders").doc(String(result.intention_order_id)).create({
        uid, plan: data.planType, amountCents, currency: "EGP",
        integrationIds: settings.integrationIds, status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {clientSecret: result.client_secret, publicKey: settings.publicKey};
    } catch (error) {
      console.error("Paymob order creation failed", error.code || "provider-error");
      throw new HttpsError("unavailable", PAYMENT_UNAVAILABLE);
    }
  });

  const paymobWebhook = onRequest({secrets: paymobEnabled ? ["PAYMOB_HMAC_SECRET"] : []}, async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("Method not allowed");
    const transaction = req.body && req.body.obj;
    if (!transaction || typeof transaction !== "object") return res.status(400).send("Missing transaction object");
    if (!paymobEnabled || !env.PAYMOB_HMAC_SECRET) return res.status(503).send("Payments unavailable");
    if (!validSignature(transaction, req.query && req.query.hmac, env.PAYMOB_HMAC_SECRET)) {
      return res.status(401).send("Invalid signature");
    }
    if (req.body.type !== "TRANSACTION" || !validId(transaction.id) ||
        !validId(transaction.order.id) || !validId(transaction.integration_id)) {
      return res.status(400).send("Invalid transaction");
    }
    // Only completed standalone sales can grant a lifetime plan.
    // Auth-only, pending, or error callbacks are ignored.
    if (transaction.pending !== false || transaction.error_occured !== false ||
        transaction.is_auth !== false || transaction.is_standalone_payment !== true ||
        transaction.has_parent_transaction !== false) {
      return res.status(200).send("Ignored");
    }

    // Handle refunds and voids by revoking the entitlement.
    const isRevocation = transaction.is_refunded === true || transaction.is_voided === true;
    const isGrant = transaction.success === true && !isRevocation;

    if (!isGrant && !isRevocation) {
      return res.status(200).send("Ignored");
    }

    try {
      const db = admin.firestore();
      const orderId = String(transaction.order.id);
      const transactionId = String(transaction.id);
      const orderRef = db.collection("paymentOrders").doc(orderId);
      const eventRef = db.collection("paymentTransactions").doc(transactionId);

      await db.runTransaction(async tx => {
        const orderDoc = await tx.get(orderRef);
        if (!orderDoc.exists) throw new HttpsError("not-found", "Unknown order");
        const order = orderDoc.data();

        if (!validPlan(order.plan) || !Number.isSafeInteger(transaction.amount_cents) ||
            transaction.amount_cents !== order.amountCents || order.amountCents !== PLANS[order.plan] ||
            transaction.currency !== order.currency || order.currency !== "EGP" ||
            !Array.isArray(order.integrationIds) || !order.integrationIds.includes(transaction.integration_id)) {
          throw new HttpsError("permission-denied", "Payment does not match order");
        }

        const event = await tx.get(eventRef);
        if (event.exists) {
          // If we already processed this exact transaction ID, don't do it again.
          return;
        }

        const userRef = db.collection("users").doc(order.uid);
        const user = await tx.get(userRef);
        if (!user.exists) throw new HttpsError("not-found", "Account no longer exists");

        const stamp = admin.firestore.FieldValue.serverTimestamp();

        if (isGrant) {
          if (order.status !== "pending") return; // Already paid or processed
          tx.update(userRef, {
            isPro: true,
            isGold: order.plan === "gold" || user.data().isGold === true,
            updatedAt: stamp,
          });
          tx.update(orderRef, {status: "paid", transactionId, paidAt: stamp});
        } else if (isRevocation) {
          // Revoke entitlement if this was the last/only purchase.
          // Note: In a real system, you might check for other active orders.
          tx.update(userRef, {
            isPro: false,
            isGold: false,
            updatedAt: stamp,
          });
          tx.update(orderRef, {status: "refunded", transactionId, refundedAt: stamp});
        }

        tx.create(eventRef, {orderId, uid: order.uid, type: isGrant ? "grant" : "revoke", processedAt: stamp});
      });
      return res.status(200).send("OK");
    } catch (error) {
      if (["permission-denied", "not-found"].includes(error.code)) return res.status(403).send("Order mismatch");
      console.error("Paymob webhook processing failed", error.code || "processing-error");
      return res.status(500).send("Processing failed");
    }
  });
  return {getPaymentCapabilities, verifyStorePurchase, createPaymobOrder, paymobWebhook};
};
