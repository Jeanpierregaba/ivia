# Aperçu local de toute la plateforme ivia, sans émulateur (peu de mémoire).
#
#   API          http://localhost:8080
#   ivia         http://localhost:3001
#   Business     http://localhost:3002
#   Livreur      http://localhost:3003
#   Pharmacie    http://localhost:3004
#   Back-office  http://localhost:3000   (admin@ivia.local, mot de passe de démo)
#
# Prérequis : Docker Desktop lancé, apps construites en web
# (voir tools/preview/README.md). Usage : powershell -File tools\preview\demarrer.ps1
# Arrêt : powershell -File tools\preview\demarrer.ps1 -Stop

param([switch]$Stop)

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$here = $PSScriptRoot
$pids = Join-Path $here '.pids'

if (Test-Path $pids) {
  Get-Content $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
  Remove-Item $pids
}
if ($Stop) { Write-Output 'Aperçu arrêté.'; return }

$started = @()

# Base PostgreSQL et Mailpit (Docker Desktop doit être lancé). Port 5434 : 5432 est réservé
# par Windows sur certains postes.
$env:POSTGRES_PORT = '5434'
Push-Location $root
docker compose up -d --wait | Out-Null
Pop-Location

# Carte : OSRM et Redis si les données sont préparées (tools/geo/preparer-osrm.sh). Sinon, itinéraires
# estimés à vol d'oiseau, sans rien de plus à faire tourner.
if (Test-Path (Join-Path $root 'geo-data\osrm-car\togo-latest.osrm.mldgr')) {
  Push-Location $root
  docker compose --profile geo up -d redis osrm-car | Out-Null
  Pop-Location
  $env:GEO_ROUTING_PROVIDER = 'osrm'
  $env:OSRM_URL = 'http://127.0.0.1:5000'
  $env:REDIS_URL = 'redis://127.0.0.1:6379/0'
}

# API locale : codes de connexion dans le journal, images servies par l'aperçu ivia.
$env:APP_ENV = 'local'
$env:OTP_SENDER = 'smtp'
$env:PUBLIC_BASE_URL = 'http://localhost:3001'
$env:DATABASE_URL = 'postgres://ivia@127.0.0.1:5434/ivia?sslmode=disable'
$env:PORT = '8080'
$env:LOCAL_STORAGE_DIR = './var/uploads'
$backend = Join-Path $root 'backend'
# Notifications push réelles (Firebase) si la clé du serveur est en place (backend\secretscm.json,
# jamais commitée) ; sinon, push écrits dans le journal.
if (Test-Path (Join-Path $backend 'secretscm.json')) {
  $env:PUSH_SENDER = 'fcm'
  $env:FCM_CREDENTIALS_FILE = 'secretscm.json'
}
$api =Start-Process -FilePath (Join-Path $backend 'bin\api.exe') -WorkingDirectory $backend -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $backend 'var\api.log') -RedirectStandardError (Join-Path $backend 'var\api.err.log') -PassThru
$started += $api.Id

# Fond de carte Google dans le navigateur : clé « navigateur » (Maps JavaScript API seulement,
# limitée à http://localhost:300x) dans tools\preview\maps-web-key.txt, non commité. Les calculs
# (itinéraires, adresses) restent sur OpenStreetMap côté serveur (ADR 0013).
# Sans ce fichier : clé GOOGLE_PLACES_API_KEY de backend\.env (lue ici, jamais affichée), qui ne sert
# alors qu'au fond de carte ; la recherche d'adresses reste sur OpenStreetMap.
$mapsKey = Join-Path $here 'maps-web-key.txt'
$backendEnv = Join-Path $root 'backend\.env'
if (Test-Path $mapsKey) {
  $env:IVIA_MAPS_WEB_KEY = (Get-Content $mapsKey -Raw).Trim()
} elseif (Test-Path $backendEnv) {
  $line = Get-Content $backendEnv | Where-Object { $_ -match '^\s*GOOGLE_PLACES_API_KEY\s*=\s*\S' } | Select-Object -First 1
  if ($line) { $env:IVIA_MAPS_WEB_KEY = ($line -split '=', 2)[1].Trim().Trim('"') }
}

# Apps Flutter (build web), avec relais vers l'API.
foreach ($app in @(@('buyer', 3001, 'ivia'), @('seller', 3002, 'Ivia Business'), @('driver', 3003, 'Ivia Driver'), @('pharmacy', 3004, 'ivia Pharmacie'))) {
  $web = Join-Path $root ('mobile\apps\' + $app[0] + '\build\web')
  $p = Start-Process -FilePath 'python' -ArgumentList @('-I', (Join-Path $here 'serve.py'), $web, $app[1], ('"' + $app[2] + '"')) `
    -WindowStyle Hidden -PassThru
  $started += $p.Id
}

# Back-office (build Next.js « standalone »).
$admin = Join-Path $root 'admin'
$standalone = Join-Path $admin '.next\standalone'
if (Test-Path $standalone) {
  Copy-Item -Recurse -Force (Join-Path $admin '.next\static') (Join-Path $standalone '.next\static')
  if (Test-Path (Join-Path $admin 'public')) { Copy-Item -Recurse -Force (Join-Path $admin 'public') (Join-Path $standalone 'public') }
  $env:API_BASE_URL = 'http://localhost:8080'
  $env:PORT = '3000'
  $env:HOSTNAME = '127.0.0.1'
  $node = Start-Process -FilePath 'node' -ArgumentList 'server.js' -WorkingDirectory $standalone -WindowStyle Hidden -PassThru
  $started += $node.Id
}

$started | Set-Content $pids
Write-Output 'Aperçu démarré :'
Write-Output '  ivia         http://localhost:3001'
Write-Output '  Business     http://localhost:3002'
Write-Output '  Livreur      http://localhost:3003'
Write-Output '  Pharmacie    http://localhost:3004'
Write-Output '  Back-office  http://localhost:3000'
