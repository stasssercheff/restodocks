'use strict';
// Замена flutter_service_worker.js: очистка кэшей и отмена регистрации SW.
// Решает проблему кэширования старых версий при F5.
self.addEventListener('install', function(e) { self.skipWaiting(); });
self.addEventListener('activate', function(e) {
  e.waitUntil((async function() {
    for (const key of await caches.keys()) { await caches.delete(key); }
    await self.clients.claim();
    await self.registration.unregister();
  })());
});
