// web/firebase-messaging-sw.js
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js");

// ---- IMPORTANT: your exact WEB config ----
firebase.initializeApp({
  apiKey: "AIzaSyAPEG1DYK9zlHZIqOgVPwEML9ph5aEFtmA",
  authDomain: "shared-calendar-5958a.firebaseapp.com",
  projectId: "shared-calendar-5958a",
  storageBucket: "shared-calendar-5958a.appspot.com",
  messagingSenderId: "548043523282",
  appId: "1:548043523282:web:1532c3030d6e61779e590b",
});

const messaging = firebase.messaging();

// Make sure this SW takes control ASAP
self.addEventListener("install", (event) => {
  self.skipWaiting();
});
self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

// Show a notification for background messages
messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || "LinkUp Calendar", {
    body: n.body || "",
    icon: "/icons/Icon-192.png",
    data: payload.data || {},
  });
});

// Optional: click behavior
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow("/"));
});
