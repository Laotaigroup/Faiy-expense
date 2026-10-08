// Service worker: ເຮັດໃຫ້ຕິດຕັ້ງແອັບໄດ້ ແລະ ເປີດໜ້າແອັບໄດ້ໄວຂຶ້ນ
// ຂໍ້ມູນ Supabase ບໍ່ຖືກເກັບໃນ cache — ດຶງຈາກເນັດທຸກຄັ້ງ
const CACHE = "faiy-expense-v2";
const SHELL = ["./", "./index.html", "./config.js", "./manifest.webmanifest", "./icon.svg", "./icon-192.png", "./icon-512.png", "./icon-180.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// ໄຟລ໌ຂອງແອັບເອງ: ລອງເນັດກ່ອນ (ໄດ້ເວີຊັນໃໝ່ສຸດ), ຖ້າບໍ່ມີເນັດໃຊ້ cache
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== self.location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); }
        return res;
      })
      .catch(() => caches.match(e.request).then(r => r || caches.match("./index.html")))
  );
});
