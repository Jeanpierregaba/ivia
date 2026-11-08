"""Aperçu local d'une app ivia (build web), affichée directement dans le navigateur.

Sert le build web (cadre iPhone facultatif sur /iphone) et relaie /v1/ et /dev/ vers l'API locale
(http://localhost:8080) : même origine, donc pas de CORS. Usage local uniquement.
"""
import http.server
import os
import sys
import urllib.error
import urllib.request

WEB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001
TITLE = sys.argv[3] if len(sys.argv) > 3 else "ivia"
FRAME = os.path.join(os.path.dirname(os.path.abspath(__file__)), "iphone17.html")
API = "http://localhost:8080"

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
            if not os.path.exists(path):
                self.path = "/index.html"
            return super().do_GET()
        self.send_error(405)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = _route


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
