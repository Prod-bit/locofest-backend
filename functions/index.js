const admin = require('firebase-admin');
admin.initializeApp();

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");

// Fonction planifiée pour supprimer les comptes non vérifiés après 7 jours
exports.deleteUnverifiedUsers = onSchedule("every 24 hours", async (event) => {
  const listUsersResult = await admin.auth().listUsers(1000);
  const now = Date.now();
  const sevenDays = 7 * 24 * 60 * 60 * 1000;
  let deleted = 0;

  for (const user of listUsersResult.users) {
    if (
      !user.emailVerified &&
      user.metadata.creationTime &&
      (now - new Date(user.metadata.creationTime).getTime() > sevenDays)
    ) {
      await admin.auth().deleteUser(user.uid);
      await admin.firestore().collection('users').doc(user.uid).delete().catch(() => {});
      deleted++;
    }
  }
  console.log(`Deleted ${deleted} unverified users`);
  return null;
});

// Limite à 100 messages par chat général
exports.limitCityChatMessages = onDocumentCreated(
  "city_chats/{cityId}/messages/{messageId}",
  async (event) => {
    const cityId = event.params.cityId;
    const messagesRef = admin.firestore()
      .collection('city_chats')
      .doc(cityId)
      .collection('messages')
      .orderBy('timestamp', 'desc');

    const snapshot = await messagesRef.get();
    if (snapshot.size > 100) {
      const docsToDelete = snapshot.docs.slice(100);
      const batch = admin.firestore().batch();
      docsToDelete.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
    }
    return null;
  }
);

// Limite à 100 messages par canal privé
exports.limitPrivateCanalMessages = onDocumentCreated(
  "private_calendars/{calendarId}/canal/{messageId}",
  async (event) => {
    const calendarId = event.params.calendarId;
    const messagesRef = admin.firestore()
      .collection('private_calendars')
      .doc(calendarId)
      .collection('canal')
      .orderBy('createdAt', 'desc');

    const snapshot = await messagesRef.get();
    if (snapshot.size > 100) {
      const docsToDelete = snapshot.docs.slice(100);
      const batch = admin.firestore().batch();
      docsToDelete.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
    }
    return null;
  }
);

// Supprime les événements trop vieux (4 jours ou 31 jours si boss/premium)
exports.deleteOldEvents = onSchedule("every 24 hours", async (event) => {
  const now = Date.now();
  const fourDays = 4 * 24 * 60 * 60 * 1000;
  const thirtyOneDays = 31 * 24 * 60 * 60 * 1000;

  const usersSnap = await admin.firestore().collection('users').get();
  const bossOrPremium = {};
  usersSnap.forEach(doc => {
    const role = doc.data().role;
    if (role === 'boss' || role === 'premium') {
      bossOrPremium[doc.id] = true;
    }
  });

  const analyticsCollections = ['views', 'event_views', 'event_participations', 'event_shares'];

  const events = await admin.firestore().collection('events').get();
  for (const eventDoc of events.docs) {
    const data = eventDoc.data();
    const ts = data.createdAt;
    const creatorId = data.creatorId;
    let delay = fourDays;
    if (creatorId && bossOrPremium[creatorId]) {
      delay = thirtyOneDays;
    }
    if (ts && ts.toDate && (now - ts.toDate().getTime() > delay)) {
      for (const subCol of analyticsCollections) {
        const subSnap = await eventDoc.ref.collection(subCol).get().catch(() => null);
        if (subSnap && !subSnap.empty) {
          const batch = admin.firestore().batch();
          subSnap.docs.forEach(doc => batch.delete(doc.ref));
          await batch.commit();
        }
      }
      await eventDoc.ref.delete();
      console.log(`Supprimé event global : ${eventDoc.id}`);
    }
  }

  const calendars = await admin.firestore().collection('private_calendars').get();
  for (const calDoc of calendars.docs) {
    const calData = calDoc.data();
    const ownerId = calData.ownerId || calData.userId;
    const isBossOrPremium = ownerId && bossOrPremium[ownerId];
    const delay = isBossOrPremium ? thirtyOneDays : fourDays;

    const subEvents = await calDoc.ref.collection('events').get();
    for (const subEvent of subEvents.docs) {
      const data = subEvent.data();
      const ts = data.createdAt;
      if (ts && ts.toDate && (now - ts.toDate().getTime() > delay)) {
        for (const subCol of analyticsCollections) {
          const subSnap = await subEvent.ref.collection(subCol).get().catch(() => null);
          if (subSnap && !subSnap.empty) {
            const batch = admin.firestore().batch();
            subSnap.docs.forEach(doc => batch.delete(doc.ref));
            await batch.commit();
          }
        }
        await subEvent.ref.delete();
        console.log(`Supprimé event privé : ${subEvent.id} dans ${calDoc.id}`);
      }
    }
  }

  return null;
});

// Supprime un événement après 150 signalements
exports.deleteEventAfterReports = onDocumentCreated(
  "event_reports/{reportId}",
  async (event) => {
    const eventId = event.data.eventId;
    if (!eventId) return null;

    const reportsSnap = await admin.firestore()
      .collection('event_reports')
      .where('eventId', '==', eventId)
      .get();

    if (reportsSnap.size >= 150) {
      await admin.firestore().collection('events').doc(eventId).delete();
      const batch = admin.firestore().batch();
      reportsSnap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      console.log(`Événement ${eventId} supprimé après 150 signalements`);
    }
    return null;
  }
);

// Bloque un utilisateur dans un city chat (boss uniquement)
exports.blockUserInCity = onCall(async (request) => {
  const data = request.data;
  const context = request.auth;

  if (!context) {
    throw new Error('Non authentifié');
  }

  const callerUid = context.uid;
  const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
  if (!callerDoc.exists || callerDoc.data().role !== 'boss') {
    throw new Error('Seuls les boss peuvent bloquer.');
  }

  const { userId, cityId, minutes } = data;
  if (!userId || !cityId) {
    throw new Error('Arguments manquants');
  }

  const targetDoc = await admin.firestore().collection('users').doc(userId).get();
  if (targetDoc.exists && targetDoc.data().role === 'boss') {
    return { ok: false, reason: 'Impossible de bloquer un boss.' };
  }

  const blockedUntil = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() + (minutes || 10) * 60000)
  );

  await admin.firestore()
    .collection('users')
    .doc(userId)
    .collection('blockedChats')
    .doc(cityId.toLowerCase())
    .set({ blockedUntil });

  return { ok: true };
});