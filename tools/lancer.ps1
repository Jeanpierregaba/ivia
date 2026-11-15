# Lance toute la plateforme ivia en une commande (aperçu local, sans émulateur).
#
#   Démarrer             powershell -ExecutionPolicy Bypass -File tools\lancer.ps1
#   Tout reconstruire    powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -Reconstruire
#   Ouvrir le navigateur powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -Ouvrir
#   Arrêter              powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -Arreter
#   Docker bloqué        powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -ReparerDocker
#                        (arrête WSL et Docker Desktop, puis relance tout ; les données restent)
#
# Ce que fait le script, dans l'ordre :
#   1. démarre Docker Desktop s'il ne tourne pas, et attend qu'il soit prêt ;
#   2. construit ce qui manque ou a changé depuis la dernière construction (API, back-office,
#      apps web) ; tout, avec -Reconstruire ;
#   3. lance l'aperçu (tools\preview\demarrer.ps1 : base, API, apps, back-office) ;
#   4. vérifie que chaque adresse répond et affiche le résultat.
# Aucun secret n'est lu ni affiché ici (les clés restent dans backend\.env, non commité).

param(
  [switch]$Reconstruire,
  [switch]$Ouvrir,
  [switch]$Arreter,
  [switch]$ReparerDocker
)

# Outils externes (docker, go, pnpm, flutter) : jugés sur leur code de retour,
# pas sur ce qu'ils écrivent sur la sortie d'erreur (avertissements).
$ErrorActionPreference = 'Continue'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$preview = Join-Path $root 'tools\preview\demarrer.ps1'
$flutter = 'C:\Mobiles_Apps\flutter\bin\flutter.bat'
$apps = @(
  @{ Nom = 'ivia (client)'; Dossier = 'buyer'; Port = 3001 },
  @{ Nom = 'Ivia Business'; Dossier = 'seller'; Port = 3002 },
  @{ Nom = 'Ivia Livreur'; Dossier = 'driver'; Port = 3003 },
  @{ Nom = 'ivia Pharmacie'; Dossier = 'pharmacy'; Port = 3004 }
)

function Etape($texte) { Write-Host "`n==> $texte" -ForegroundColor Cyan }
function Ok($texte) { Write-Host "    OK  $texte" -ForegroundColor Green }
function Ko($texte) { Write-Host "    !!  $texte" -ForegroundColor Yellow }

# Docker répond-il ? Abandonne après 10 s : un Docker bloqué ne répond jamais.
function DockerPret {
  $p = Start-Process -FilePath 'docker' -ArgumentList 'info' -WindowStyle Hidden -PassThru
  if (-not $p.WaitForExit(10000)) {
    try { $p.Kill() } catch {}
    return $false
  }
  return ($p.ExitCode -eq 0)
}

function DemarrerDocker {
  $exe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
  if (-not (Test-Path $exe)) { throw "Docker Desktop introuvable ($exe)." }
  Start-Process $exe
}

# Sources modifiées après la construction [cible] (ou cible absente) ?
function AChange($cible, [string[]]$dossiers, [string[]]$motifs) {
  if (-not (Test-Path $cible)) { return $true }
  $date = (Get-Item $cible).LastWriteTime
  foreach ($d in $dossiers) {
    if (-not (Test-Path $d)) { continue }
    $recent = Get-ChildItem -Path $d -Recurse -File -Include $motifs -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch '\\(build|node_modules|\.next|\.dart_tool)\\' -and $_.LastWriteTime -gt $date } |
      Select-Object -First 1
    if ($recent) { return $true }
  }
  return $false
}

function Repond($url) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 4 -MaximumRedirection 0 -ErrorAction Stop
    return $r.StatusCode -lt 500
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    return ($code -ge 200 -and $code -lt 500)
  }
}

if ($Arreter) {
  & powershell -ExecutionPolicy Bypass -File $preview -Stop
  return
}

# 1. Docker Desktop
Etape 'Docker'
if ($ReparerDocker) {
  Write-Host '    Arrêt de l''aperçu, de Docker Desktop et de WSL...'
  & powershell -ExecutionPolicy Bypass -File $preview -Stop *> $null
  Get-Process 'Docker Desktop', 'com.docker.backend', 'com.docker.build' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  wsl --shutdown
  Start-Sleep -Seconds 5
}
$dockerOk = DockerPret
if (-not $dockerOk) {
  Write-Host '    Démarrage de Docker Desktop (1 à 2 minutes)...'
  DemarrerDocker
  $limite = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $limite) {
    Start-Sleep -Seconds 5
    if (DockerPret) { $dockerOk = $true; break }
  }
  if (-not $dockerOk) {
    Write-Host ''
    Write-Host 'Docker ne répond pas (souvent : Docker bloqué faute de mémoire).' -ForegroundColor Yellow
    Write-Host 'Lancez « Reparer Docker ivia » sur le bureau, ou :' -ForegroundColor Yellow
    Write-Host '  powershell -ExecutionPolicy Bypass -File tools\lancer.ps1 -ReparerDocker' -ForegroundColor Yellow
    exit 1
  }
}
Ok 'Docker est prêt'

# 2. Constructions (ce qui manque, ou tout avec -Reconstruire)
Etape 'Constructions'
$api = Join-Path $root 'backend\bin\api.exe'
$backend = Join-Path $root 'backend'
if ($Reconstruire -or (AChange $api @((Join-Path $backend 'cmd'), (Join-Path $backend 'internal'), (Join-Path $backend 'db')) @('*.go', '*.sql'))) {
  Write-Host '    API (Go)...'
  & powershell -ExecutionPolicy Bypass -File $preview -Stop *> $null
  Push-Location (Join-Path $root 'backend')
  $env:GOMAXPROCS = '2'
  cmd /c "go build -o bin\api.exe .\cmd\api"
  $code = $LASTEXITCODE
  Pop-Location
  if ($code -ne 0) { throw "La construction de l'API a échoué." }
  Ok 'API construite'
} else { Ok 'API à jour' }

$standalone = Join-Path $root 'admin\.next\standalone\server.js'
$adminDir = Join-Path $root 'admin'
if ($Reconstruire -or (AChange $standalone @((Join-Path $adminDir 'app'), (Join-Path $adminDir 'components'), (Join-Path $adminDir 'lib'), (Join-Path $adminDir 'public')) @('*.ts', '*.tsx', '*.css', '*.png', '*.ico'))) {
  Write-Host '    Back-office (Next.js, quelques minutes)...'
  & powershell -ExecutionPolicy Bypass -File $preview -Stop *> $null
  Push-Location (Join-Path $root 'admin')
  cmd /c "pnpm build >nul 2>&1"
  $code = $LASTEXITCODE
  Pop-Location
  if ($code -ne 0) { throw "La construction du back-office a échoué (lancez « pnpm build » dans admin pour voir l'erreur)." }
  Ok 'Back-office construit'
} else { Ok 'Back-office à jour' }

# Fond de carte Google dans les apps web si une clé est en place (jamais affichée).
$cartes = @()
$cle = Join-Path $root 'tools\preview\maps-web-key.txt'
$envFile = Join-Path $root 'backend\.env'
$aCle = (Test-Path $cle) -or ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern '^\s*GOOGLE_PLACES_API_KEY\s*=\s*\S' -Quiet))
if ($aCle) { $cartes = @('--dart-define=IVIA_GOOGLE_MAPS=true', '--dart-define=GOOGLE_MAPS=true') }

foreach ($a in $apps) {
  $dossier = Join-Path $root ('mobile\apps\' + $a.Dossier)
  $sortie = Join-Path $dossier 'build\web\main.dart.js'
  $sources = @((Join-Path $dossier 'lib'), (Join-Path $dossier 'web'), (Join-Path $root 'mobile\packages'))
  if ($Reconstruire -or (AChange $sortie $sources @('*.dart', '*.png', '*.html', '*.json'))) {
    Write-Host "    $($a.Nom) (Flutter web, 3 à 6 minutes)..."
    Push-Location $dossier
    $fargs = @('build', 'web', '--profile', '--no-web-resources-cdn',
      "--dart-define=API_BASE_URL=http://localhost:$($a.Port)",
      '--dart-define=IVIA_DEV_OTP=true', '--dart-define=IVIA_DEV_PAYMENT=true') + $cartes
    cmd /c "`"$flutter`" $($fargs -join ' ') >nul 2>&1"
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Ko "$($a.Nom) : construction échouée (voir « flutter build web » dans mobile\apps\$($a.Dossier))" }
    else { Ok "$($a.Nom) construite" }
  } else { Ok "$($a.Nom) à jour" }
}

# 3. Aperçu
Etape 'Démarrage des serveurs'
# Lancé à part : les serveurs démarrés tournent en arrière-plan et ce script
# ne fait qu'attendre qu'ils répondent.
Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $preview) -WindowStyle Hidden
Write-Host '    Base, API, apps et back-office en cours de démarrage...'

# 4. Vérifications
Etape 'Vérifications'
$limite = (Get-Date).AddMinutes(4)
while ((Get-Date) -lt $limite -and -not (Repond 'http://localhost:8080/ready')) { Start-Sleep -Seconds 3 }
if (Repond 'http://localhost:8080/ready') { Ok 'API          http://localhost:8080' } else { Ko "API          http://localhost:8080 ne répond pas (journal : backend\var\api.err.log)" }
Start-Sleep -Seconds 2
foreach ($a in $apps) {
  $url = "http://localhost:$($a.Port)"
  if (Repond $url) { Ok ("{0,-13}{1}" -f $a.Nom, $url) } else { Ko ("{0,-13}{1} ne répond pas" -f $a.Nom, $url) }
}
$bo = 'http://localhost:3000'
$t = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $t -and -not (Repond $bo)) { Start-Sleep -Seconds 2 }
if (Repond $bo) { Ok "Back-office  $bo" } else { Ko "Back-office  $bo ne répond pas" }

Write-Host "`nTout est lancé. Pour arrêter : tools\lancer.ps1 -Arreter (ou « Arreter ivia » sur le bureau)." -ForegroundColor Cyan
Write-Host 'Codes de connexion de démonstration : affichés dans backend\var\api.log (local seulement).'
if ($Ouvrir) {
  Start-Process $bo
  foreach ($a in $apps) { Start-Process "http://localhost:$($a.Port)" }
}
