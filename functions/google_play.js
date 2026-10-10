const crypto = require("node:crypto");
const {GoogleAuth} = require("google-auth-library");

const PACKAGE_NAME = "com.ghandour.na2slna";
const PRODUCTS = Object.freeze({
  na2slna_pro_lifetime: "pro",
  na2slna_gold_lifetime: "gold",
});
const BASE_URL = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}`;
const hash = value => crypto.createHash("sha256").update(value).digest("hex");

// Application Default Credentials use the function's service account. No private
// key or Google Play credential belongs in the app or in source control.
exports.createGooglePlayClient = () => {
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/androidpublisher"]});
  return {request: async options => (await auth.getClient()).request({
    ...options, timeout: 15000, retry: false,
  })};
};

exports.createGooglePlayVerifier = ({admin, HttpsError, client}) => {
  const providerRequest = async options => {
    try {
      return (await client.request(options)).data;
    } catch (error) {
      // Google's error object can contain the token in a request URL: never log it.
      const status = error.response && error.response.status;
      if ([400, 404, 410].includes(status)) {
        throw new HttpsError("invalid-argument", "Google Play could not verify this purchase.");
      }
      if ([401, 403].includes(status)) {
        console.error("Google Play verification service lacks access", status);
        throw new HttpsError("failed-precondition", "Purchase verification is temporarily unavailable.");
      }
      console.error("Google Play verification service unavailable", status || "network-error");
      throw new HttpsError("unavailable", "Could not reach Google Play. Please restore your purchase later.");
    }
  };

  return async request => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Please sign in before purchasing.");
    const data = request.data || {};
    if (data.userId !== undefined && data.userId !== uid) {
      throw new HttpsError("permission-denied", "A purchase must belong to the signed-in account.");
    }
    if (data.source !== "google_play") {
      throw new HttpsError("failed-precondition", "This store is not supported by the purchase verifier yet.");
    }
    if (typeof data.productId !== "string" || !Object.hasOwn(PRODUCTS, data.productId)) {
      throw new HttpsError("invalid-argument", "Choose a valid plan.");
    }
    const token = data.verificationData;
    if (typeof token !== "string" || !token || token.length > 8192 || /\s/.test(token)) {
      throw new HttpsError("invalid-argument", "A Google Play purchase token is required.");
    }
    const url = `${BASE_URL}/purchases/productsv2/tokens/${encodeURIComponent(token)}`;
    // Always recheck with Google, including restores and previously recorded tokens.
    // Client purchaseId/status/price are never evidence of a successful payment.
    const purchase = await providerRequest({method: "GET", url});
    const state = purchase && purchase.purchaseStateContext && purchase.purchaseStateContext.purchaseState;
    if (state !== "PURCHASED") {
      throw new HttpsError("failed-precondition", state === "PENDING" ?
        "Your payment is still pending in Google Play." : "This purchase is not active in Google Play.");
    }
    const lines = purchase.productLineItem;
    if (!Array.isArray(lines) || lines.length !== 1 || lines[0].productId !== data.productId) {
      throw new HttpsError("permission-denied", "The purchased product does not match this plan.");
    }
    const offer = lines[0].productOfferDetails || {};
    if (offer.rentOfferDetails || offer.consumptionState === "CONSUMPTION_STATE_CONSUMED" ||
        (offer.quantity !== undefined && offer.quantity !== 1) ||
        (offer.refundableQuantity !== undefined && offer.refundableQuantity !== 1)) {
      throw new HttpsError("failed-precondition", "This purchase is not an active lifetime plan.");
    }
    if (!["ACKNOWLEDGEMENT_STATE_PENDING", "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"].includes(purchase.acknowledgementState)) {
      throw new HttpsError("unavailable", "Google Play returned an incomplete purchase. Please try again.");
    }
    // New builds hash the Firebase UID. Accept the raw UID used by existing builds.
    // Older purchases without an account ID may be claimed once with a Google-
    // verified token; the atomic server record then binds all restores to that UID.
    const accountId = purchase.obfuscatedExternalAccountId;
    if (accountId && accountId !== hash(uid) && accountId !== uid) {
      throw new HttpsError("permission-denied", "Sign in to the account that bought this plan.");
    }
    const db = admin.firestore();
    const receiptRef = db.collection("storePurchases").doc(hash(`google_play:${PACKAGE_NAME}:${token}`));
    const userRef = db.collection("users").doc(uid);
    await db.runTransaction(async tx => {
      const receipt = await tx.get(receiptRef);
      const user = await tx.get(userRef);
      if (!user.exists) throw new HttpsError("failed-precondition", "Complete your profile before restoring purchases.");
      if (receipt.exists && (receipt.data().uid !== uid || receipt.data().productId !== data.productId)) {
        throw new HttpsError("permission-denied", "This purchase already belongs to another account.");
      }
      const stamp = admin.firestore.FieldValue.serverTimestamp();
      if (!receipt.exists) {
        tx.create(receiptRef, {
          uid, productId: data.productId, packageName: PACKAGE_NAME, source: "google_play",
          orderId: purchase.orderId || null, testPurchase: Boolean(purchase.testPurchaseContext),
          verifiedAt: stamp, acknowledged: false,
        });
      }
      // Pro restores must never remove a Gold plan bought through either provider.
      tx.update(userRef, {
        isPro: true, isGold: PRODUCTS[data.productId] === "gold" || user.data().isGold === true,
        updatedAt: stamp,
      });
    });

    // Grant first, then acknowledge on the server. If Google or this final write
    // fails, retrying the same token safely resumes without moving its ownership.
    if (purchase.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") {
      try {
        await providerRequest({method: "POST",
          url: `${BASE_URL}/purchases/products/${encodeURIComponent(data.productId)}/tokens/${encodeURIComponent(token)}:acknowledge`,
          data: {},
        });
      } catch (error) {
        // A concurrent restore/older client may already have acknowledged it.
        const refreshed = await providerRequest({method: "GET", url});
        if (!refreshed || refreshed.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" ||
            !refreshed.purchaseStateContext || refreshed.purchaseStateContext.purchaseState !== "PURCHASED") throw error;
      }
    }
    await receiptRef.update({acknowledged: true, acknowledgedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {verified: true, acknowledged: true};
  };
};

exports.PACKAGE_NAME = PACKAGE_NAME;
exports.PRODUCTS = PRODUCTS;
