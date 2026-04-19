// Service Worker — Autism Support UI (P-UI-2)
// Cache strategy:
//   CDN assets  → Cache First (pre-cached on install)
//   index.html  → Network First with cache fallback
//   /api/search, /api/insights*, /api/weekly-summary → Network First, cache last response (max 5 per endpoint)
//   /api/search/stream (SSE) → Network Only
//   /collect/*  → Network Only (write operations must never be stale)
//   all others  → Network Only

const STATIC_CACHE  = 'mzhu-static-v1';
const DYNAMIC_CACHE = 'mzhu-dynamic-v1';
const MAX_SEARCH_CACHE = 5;

const CDN_URLS = [
  'https://cdn.tailwindcss.com',
  'https://cdn.jsdelivr.net/npm/marked/marked.min.js',
  'https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js',
];

const NETWORK_FIRST_PATTERNS = [
  /\/api\/search(\?|$)/,
  /\/api\/insights/,
  /\/api\/weekly-summary/,
];

// Skip SSE streams, collect writes, and other API calls
const NETWORK_ONLY_PATTERNS = [
  /\/api\/search\/stream/,
  /\/collect\//,
  /\/api\/evidence/,
  /\/api\/sources/,
  /\/api\/stats/,
  /\/api\/health/,
  /\/api\/clinician-report/,
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then(cache => {
      return Promise.allSettled(CDN_URLS.map(url => cache.add(url)));
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  const valid = [STATIC_CACHE, DYNAMIC_CACHE];
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => !valid.includes(k)).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Only handle GET requests (POST/PUT/OPTIONS pass through)
  if (request.method !== 'GET') return;

  // CDN assets — Cache First
  if (CDN_URLS.some(u => request.url.startsWith(u))) {
    event.respondWith(
      caches.match(request).then(cached => cached || fetch(request).then(resp => {
        const clone = resp.clone();
        caches.open(STATIC_CACHE).then(c => c.put(request, clone));
        return resp;
      }))
    );
    return;
  }

  // Network Only patterns — pass straight through
  if (NETWORK_ONLY_PATTERNS.some(p => p.test(url.pathname + url.search))) return;

  // index.html — Network First
  if (url.pathname === '/' || url.pathname === '/index.html') {
    event.respondWith(
      fetch(request).then(resp => {
        const clone = resp.clone();
        caches.open(STATIC_CACHE).then(c => c.put(request, clone));
        return resp;
      }).catch(() => caches.match(request))
    );
    return;
  }

  // Network First patterns — cache last successful response
  if (NETWORK_FIRST_PATTERNS.some(p => p.test(url.pathname + url.search))) {
    event.respondWith(
      fetch(request).then(async resp => {
        if (resp.ok) {
          const cache = await caches.open(DYNAMIC_CACHE);
          // Enforce max 5 cached search URLs by evicting oldest
          const keys = await cache.keys();
          const searchKeys = keys.filter(k => /\/api\/search(\?|$)/.test(new URL(k.url).pathname + new URL(k.url).search));
          if (searchKeys.length >= MAX_SEARCH_CACHE) {
            await cache.delete(searchKeys[0]);
          }
          cache.put(request, resp.clone());
        }
        return resp;
      }).catch(async () => {
        const cached = await caches.match(request);
        if (cached) {
          // Add header so UI can detect offline-served response
          const headers = new Headers(cached.headers);
          headers.set('X-Served-From', 'cache');
          return new Response(cached.body, { status: cached.status, headers });
        }
        return new Response(JSON.stringify({ error: 'Offline and no cached response available.' }), {
          status: 503, headers: { 'Content-Type': 'application/json' }
        });
      })
    );
    return;
  }
});
