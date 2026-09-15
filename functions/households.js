const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const INVITE_LIFETIME_MS = 48 * 60 * 60 * 1000;

// Membership changes run on the server so clients cannot choose their own role,
// bypass invitation expiry, or race each other past the household member limit.
exports.joinHousehold = onCall({region: "us-central1"}, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign in before joining a household.");
  }

  const uid = request.auth.uid;
  const suppliedCode = request.data && request.data.inviteCode;
  const inviteCode = typeof suppliedCode === "string" ?
    suppliedCode.trim().toUpperCase() : "";
  if (!/^[A-Z0-9]{6}$/.test(inviteCode)) {
    throw new HttpsError("invalid-argument", "Enter a six-character invite code.", {
      reason: "invalid-invite-code",
    });
  }

  const db = admin.firestore();
  return db.runTransaction(async (transaction) => {
    const invite = await transaction.get(db.collection("inviteCodes").doc(inviteCode));
    if (!invite.exists) {
      throw new HttpsError("not-found", "Invalid invite code.", {
        reason: "invite-not-found",
      });
    }

    const inviteData = invite.data();
    const createdAt = inviteData.createdAt;
    const age = createdAt instanceof admin.firestore.Timestamp ?
      Date.now() - createdAt.toMillis() : NaN;
    if (!Number.isFinite(age) || age < 0 || age > INVITE_LIFETIME_MS) {
      throw new HttpsError("failed-precondition", "This invite code has expired.", {
        reason: "invite-expired",
      });
    }

    const householdId = inviteData.householdId;
    if (typeof householdId !== "string" || !householdId || householdId.includes("/")) {
      throw new HttpsError("not-found", "Household no longer exists.", {
        reason: "household-not-found",
      });
    }

    const householdRef = db.collection("households").doc(householdId);
    const household = await transaction.get(householdRef);
    if (!household.exists) {
      throw new HttpsError("not-found", "Household no longer exists.", {
        reason: "household-not-found",
      });
    }
    if (household.data().inviteCode !== inviteCode) {
      throw new HttpsError("not-found", "This invite code is no longer active.", {
        reason: "invite-not-found",
      });
    }

    const userRef = db.collection("users").doc(uid);
    const user = await transaction.get(userRef);
    if (!user.exists) {
      throw new HttpsError("failed-precondition", "Create your profile before joining.", {
        reason: "user-not-found",
      });
    }

    const ownerId = household.data().createdBy;
    const isOwner = ownerId === uid;
    if (user.data().householdId === householdId) {
      // Opening your own invite is idempotent, including at full capacity.
      if (isOwner && user.data().role !== "familyAdmin") {
        transaction.update(userRef, {
          role: "familyAdmin",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        transaction.update(householdRef, {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      return {householdId};
    }

    let owner;
    if (isOwner) {
      owner = user;
    } else if (typeof ownerId === "string" && ownerId && !ownerId.includes("/")) {
      owner = await transaction.get(db.collection("users").doc(ownerId));
    }
    const ownerData = owner && owner.exists ? owner.data() : {};
    const unlimited = ownerData.isGold === true && ownerData.householdId === householdId;
    const members = await transaction.get(
        db.collection("users").where("householdId", "==", householdId),
    );
    if (!unlimited && members.size >= 5) {
      throw new HttpsError("resource-exhausted", "This household has reached the 5-member limit.", {
        reason: "limit-reached",
      });
    }

    transaction.update(userRef, {
      householdId,
      role: isOwner ? "familyAdmin" : "familyMember",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Every successful new join writes the shared household document. A
    // concurrent join must retry against the committed membership count.
    transaction.update(householdRef, {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {householdId};
  });
});
