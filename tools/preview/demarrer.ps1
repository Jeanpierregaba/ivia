# Aperçu local de toute la plateforme ivia, sans émulateur (peu de mémoire).
#
#   API          http://localhost:8080
#   Acheteur     http://localhost:8090   (cadre iPhone 17 Pro)
#   Business     http://localhost:8091
#   Livreur      http://localhost:8092
#   Pharmacie    http://localhost:8093
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
if (Test-Path (Join-Path $root 'geo-data\osrm-car	ogo-latest.osrm.mldgr')) {
  Push-Location $root
  docker compose --profile geo up -d redis osrm-car | Out-Null
  Pop-Location
  $env:GEO_ROUTING_PROVIDER = 'osrm'
  $env:OSRM_URL = 'http://127.0.0.1:5000'
  $env:REDIS_URL = 'redis://127.0.0.1:6379/0'
}

# API locale : codes de connexion dans le journal, images servies par l'aperçu acheteur.
$env:APP_ENV = 'local'
$env:OTP_SENDER = 'smtp'
$env:PUBLIC_BASE_URL = 'http://localhost:8090'
$env:DATABASE_URL = 'postgres://ivia@127.0.0.1:5434/ivia?sslmode=disable'
$env:PORT = '8080'
$env:LOCAL_STORAGE_DIR = './var/uploads'
$backend = Join-Path $root 'backend'
$api = Start-Process -FilePath (Join-Path $backend 'bin\api.exe') -WorkingDirectory $backend -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $backend 'var\api.log') -RedirectStandardError (Join-Path $backend 'var\api.err.log') -PassThru
$started += $api.Id

# Apps Flutter (build web) dans le cadre iPhone, avec relais vers l'API.
foreach ($app in @(@('buyer', 8090, 'ivia Acheteur'), @('seller', 8091, 'Ivia Business'), @('driver', 8092, 'ivia Livreur'), @('pharmacy', 8093, 'ivia Pharmacie'))) {
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
Write-Output '  Acheteur     http://localhost:8090'
Write-Output '  Business     http://localhost:8091'
Write-Output '  Livreur      http://localhost:8092'
Write-Output '  Pharmacie    http://localhost:8093'
Write-Output '  Back-office  http://localhost:3000'
