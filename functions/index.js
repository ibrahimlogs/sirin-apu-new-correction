const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

async function deleteDailyStepSummaries(db, uid) {
  const batchSize = 300;

  while (true) {
    const snapshot = await db
      .collection("daily_steps_summary")
      .where("uid", "==", uid)
      .limit(batchSize)
      .get();

    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    if (snapshot.size < batchSize) {
      return;
    }
  }
}

exports.deleteMyAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const db = getFirestore();

    try {
      await deleteDailyStepSummaries(db, uid);
      await db.collection("users").doc(uid).delete();
      await getAuth().deleteUser(uid);
      return { success: true };
    } catch (error) {
      console.error("deleteMyAccount failed", { uid, error });
      throw new HttpsError(
        "internal",
        "Failed to delete account. Please try again.",
      );
    }
  },
);