// Planer — offline shell cache. Kept as a real same-origin file because
// browsers refuse to register a service worker from a blob: URL (the
// single-file app itself is still just index.html; this file only exists for
// the hosted/HTTPS deployment and is never touched when opened via file://).
//
// Network-first, cache-fallback: always try the network so an installed PWA
// picks up new deploys, and only fall back to the cache when offline.
// Bump this on every release that changes index.html. `activate` deletes every
// cache whose name differs from this constant, so the bump is what actually
// evicts the previous shell — leave it alone and an installed PWA can keep
// serving the old app from cache long after a deploy.
const CACHE = 'planer-shell-v8-web-push';

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
  // Authentication and API responses must never be placed in the PWA shell
  // cache. The app shell is same-origin; Supabase is deliberately cross-origin.
  if (new URL(e.request.url).origin !== self.location.origin) return;
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

// A Push event is delivered even while the PWA is not open. The server sends
// only display data and a same-origin navigation target; account data remains
// behind the normal authenticated application flow.
self.addEventListener('push', (event) => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch {}
  const title = String(payload.title || 'Planer');
  const options = {
    body: String(payload.body || ''),
    icon: './app-icon-192.png',
    badge: './app-icon-192.png',
    tag: String(payload.tag || 'planer'),
    renotify: false,
    data: { url: typeof payload.url === 'string' ? payload.url : './#/today' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || './#/today', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if ('navigate' in client) await client.navigate(target);
      return client.focus();
    }
    return clients.openWindow(target);
  })());
});
