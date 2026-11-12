"""Aperçu local d'une app ivia (build web), affichée directement dans le navigateur.

Sert le build web (cadre iPhone facultatif sur /iphone) et relaie /v1/ et /dev/ vers l'API locale
(http://localhost:8080) : même origine, donc pas de CORS. Usage local uniquement.
"""
import http.server
import json
import os
import re
import sys
import urllib.error
import urllib.request

WEB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001
TITLE = sys.argv[3] if len(sys.argv) > 3 else "ivia"
FRAME = os.path.join(os.path.dirname(os.path.abspath(__file__)), "iphone17.html")
API = "http://localhost:8080"
# Clé Google « navigateur » du fond de carte (voir demarrer.ps1) ; absente : tuiles OpenStreetMap.
MAPS_KEY = os.environ.get("IVIA_MAPS_WEB_KEY", "").strip()
# Push dans le navigateur : bloc firebaseConfig de la console Firebase et clé Web Push (dernière ligne)
# dans tools/preview/firebase-web.txt, non commité. Absent : pas de push dans l'aperçu.
FIREBASE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "firebase-web.txt")


def firebase_config():
    if not os.path.exists(FIREBASE_FILE):
        return None
    text = open(FIREBASE_FILE, encoding="utf-8").read()
    cfg = dict(re.findall(r"""(\w+)\s*:\s*["']([^"']+)["']""", text))
    for line in reversed(text.splitlines()):
        key = line.strip().strip("\"';,")
        if re.fullmatch(r"[A-Za-z0-9_-]{60,}", key):
            cfg["vapidKey"] = key
            break
    return cfg if cfg.get("apiKey") and cfg.get("appId") else None


def firebase_worker(cfg):
    return ("""importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((pages) =>
    pages.length > 0 ? pages[0].focus() : clients.openWindow('/')));
});
firebase.initializeApp(%s);
firebase.messaging();
""" % json.dumps({k: v for k, v in cfg.items() if k != "vapidKey"})).encode()

# Service worker de remplacement : Flutter en installe un qui garde les anciens builds en cache, et
# l'aperçu doit toujours montrer le dernier. Celui-ci vide le cache puis se retire. La page ne se
# recharge que si un cache a été vidé : sinon, elle se rechargerait sans fin.
NO_SERVICE_WORKER = b"""
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil((async () => {
  const names = await caches.keys();
  await Promise.all(names.map((name) => caches.delete(name)));
  await self.registration.unregister();
  if (names.length > 0) {
    const pages = await self.clients.matchAll({ type: 'window' });
    pages.forEach((page) => page.navigate(page.url));
  }
})()));
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=WEB, **kw)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):  # pas de journal (jetons dans les en-têtes)
        pass

    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "content-length", "connection")}
        req = urllib.request.Request(API + self.path, data=body, headers=headers, method=self.command)
        try:
            resp = urllib.request.urlopen(req, timeout=30)
            status, rheaders, data = resp.status, resp.getheaders(), resp.read()
        except urllib.error.HTTPError as e:
            status, rheaders, data = e.code, e.headers.items(), e.read()
        except Exception:
            status, rheaders, data = 502, [("Content-Type", "application/json")], b'{"error":{"code":"api_down","message":"API locale injoignable."}}'
        self.send_response(status)
        for k, v in rheaders:
            if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(k, v)
        # Apps servies sur les autres ports (marchand, livreur) : même API, local uniquement.
        self._cors()
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _cors(self):
        origin = self.headers.get("Origin", "")
        if origin.startswith("http://localhost:"):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
            self.send_header("Vary", "Origin")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _route(self):
        if self.path.startswith("/v1/") or self.path.startswith("/dev/"):
            return self._proxy()
        if self.path == "/iphone":
            data = open(FRAME, "rb").read().replace(b"<h1>ivia", b"<h1>" + TITLE.encode())
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path.split("?")[0] == "/firebase-messaging-sw.js":
            cfg = firebase_config()
            if cfg is None:
                return self.send_error(404)
            data = firebase_worker(cfg)
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path.split("?")[0] == "/flutter_service_worker.js":
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript")
            self.send_header("Content-Length", str(len(NO_SERVICE_WORKER)))
            self.end_headers()
            self.wfile.write(NO_SERVICE_WORKER)
            return
        if self.command == "GET":
            # Routes de l'app (go_router) : index.html.
            path = self.translate_path(self.path.split("?")[0])
            if not os.path.exists(path) or self.path.split("?")[0] in ("/", "/index.html"):
                return self._index()
            return super().do_GET()
        self.send_error(405)

    def _index(self):
        data = open(os.path.join(WEB, "index.html"), "rb").read()
        if MAPS_KEY:
            tag = '<script src="https://maps.googleapis.com/maps/api/js?key=%s"></script>' % MAPS_KEY
            data = data.replace(b"</head>", tag.encode() + b"</head>", 1)
        cfg = firebase_config()
        if cfg:
            tag = "<script>window.iviaFirebase = %s;</script>" % json.dumps(cfg)
            data = data.replace(b"</head>", tag.encode() + b"</head>", 1)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _route


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
