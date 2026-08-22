// Service worker enkel voor de app-shell van de PrevX app (app.html, manifest,
// logo) -- vereist voor de "installeren als app"-prompt van Chrome/Android.
// Bewust NIET van toepassing op de rest van prevx.be (de marketingsite) of op
// Supabase-aanroepen: alles buiten APP_SHELL loopt gewoon rechtstreeks over het
// netwerk, ongecached.
//
// De oude paden /pre-insp blijven in de lijst staan: reeds geïnstalleerde apps
// starten daar nog en worden door een doorverwijzing naar /app gestuurd. Ze
// mogen pas weg wanneer niemand nog een oude installatie heeft.

var CACHE_NAME = 'prevx-app-v5';
var APP_SHELL = ['/app', '/app.html', '/pre-insp', '/pre-insp.html', '/manifest.json', '/Logo-PrevX.png'];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(APP_SHELL);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== CACHE_NAME; }).map(function (k) { return caches.delete(k); }));
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function (event) {
  var url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || APP_SHELL.indexOf(url.pathname) === -1) {
    return;
  }
  // Netwerk-eerst, cache enkel als offline-terugval -- anders blijft een
  // geïnstalleerde PWA na elke update van app.html de oude versie tonen
  // tot een tweede herlaad (precies de bug die dit moest oplossen).
  // cache:'no-store' erbij: zonder dat gaat deze fetch alsnog door de
  // HTTP-cache van de browser, die een oude kopie kan teruggeven. Dan is
  // "netwerk-eerst" maar de helft waar en blijft een geinstalleerde app na een
  // uitrol de vorige versie tonen -- precies de fout die dit moest oplossen.
  event.respondWith(
    fetch(event.request, { cache: 'no-store' })
      .then(function (resp) {
        caches.open(CACHE_NAME).then(function (cache) { cache.put(event.request, resp.clone()); });
        return resp;
      })
      .catch(function () { return caches.match(event.request); })
  );
});

// ---------------------------------------------------------------------------
// Pushmeldingen voor de nazorgcontrole na heet werk
// ---------------------------------------------------------------------------
// De inhoud is versleuteld tussen de server en dit toestel; de pushdienst van
// Google of Apple ziet ze niet. Toch blijft de tekst bewust kort en zonder
// werkplek: dit verschijnt op een vergrendeld scherm dat ook een collega of
// een huisgenoot kan zien. Het vergunningsnummer volstaat om te weten waarover
// het gaat; wie meer nodig heeft, opent de app.

self.addEventListener('push', function (event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = {}; }

  var titel = data.titel || 'Nazorgcontrole vereist';
  var opties = {
    body: data.tekst || 'Open de PrevX app om de controle te bevestigen.',
    icon: '/Logo-PrevX.png',
    badge: '/Logo-PrevX.png',
    tag: data.tag || 'nazorg',
    // Een gemiste nazorgcontrole is precies het scenario waarin een melding
    // niet vanzelf mag wegvallen: hij blijft staan tot iemand hem wegklikt.
    requireInteraction: true,
    data: { url: data.url || '/app' }
  };
  event.waitUntil(self.registration.showNotification(titel, opties));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var doel = (event.notification.data && event.notification.data.url) || '/app';

  // Een al openstaande app naar voren halen i.p.v. een tweede venster openen:
  // anders staat de chauffeur in een verse sessie en moet hij opnieuw inloggen
  // terwijl hij net iets moet bevestigen.
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (lijst) {
      for (var i = 0; i < lijst.length; i++) {
        if (lijst[i].url.indexOf(self.location.origin) === 0 && 'focus' in lijst[i]) {
          return lijst[i].focus();
        }
      }
      return self.clients.openWindow(doel);
    })
  );
});
