// Life OS — offline shell cache. Kept as a real same-origin file because
// browsers refuse to register a service worker from a blob: URL (the
// single-file app itself is still just index.html; this file only exists for
// the hosted/HTTPS deployment and is never touched when opened via file://).
//
// Network-first, cache-fallback: always try the network so an installed PWA
// picks up new deploys, and only fall back to the cache when offline.
const CACHE = 'lifeos-shell-v1';

self.addEventListener('install', () => { self.skipWaiting(); });

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(e.request).then((r) => r || caches.match('./')))
  );
});
