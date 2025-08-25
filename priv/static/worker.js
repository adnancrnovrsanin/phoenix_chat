// Minimal no-op service worker to avoid 404s on /worker.js
// This can be replaced with a real SW if/when needed.
self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", (event) => {
  // No caching; passthrough
});
