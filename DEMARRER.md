# Démarrer tout le projet en local

Toute la plateforme tourne sur un seul PC, dans le navigateur, sans émulateur : API, back-office et
les 4 apps mobiles (affichées dans un cadre iPhone).

Toutes les commandes se tapent dans **PowerShell**. Le dossier où les taper est indiqué à chaque
fois ; « racine » désigne le dossier du dépôt, `C:\Users\<vous>\Desktop\ivia\ivia` (celui qui
contient `backend`, `admin`, `mobile` et `docker-compose.yml`).

## Au quotidien : tout est déjà construit

1. Ouvrir **Docker Desktop** et attendre qu'il indique « Engine running » (1 à 2 minutes).
2. Depuis la **racine** :

   ```powershell
   powershell -File tools\preview\demarrer.ps1
   ```

   Le script lance la base de données et Mailpit (Docker), l'API, le back-office et les 4 apps. Compter
   30 à 60 secondes avant que tout réponde.

3. Ouvrir les adresses :

   | Service | Adresse |
   | --- | --- |
   | ivia (app client) | http://localhost:8090 |
   | Ivia Business | http://localhost:8091 |
   | Livreur | http://localhost:8092 |
   | Pharmacie | http://localhost:8093 |
   | Back-office | http://localhost:3000 |
   | API | http://localhost:8080 |
   | Documentation de l'API (Swagger) | http://localhost:8080/docs |
   | E-mails reçus (Mailpit) | http://localhost:8025 |

**Arrêter tout**, depuis la **racine** :

```powershell
powershell -File tools\preview\demarrer.ps1 -Stop
```

Docker Desktop peut rester ouvert.

## La première fois (ou après un `git pull`)

### Prérequis à installer une fois

Docker Desktop, Go, Node.js avec pnpm, Flutter et Python.

### 1. Construire l'API

Depuis **`backend`** :

```powershell
go build -o bin/api.exe ./cmd/api
go build -o bin/manage.exe ./cmd/manage
```

Les migrations de la base s'appliquent toutes seules au démarrage de l'API.

### 2. Construire le back-office

Depuis **`admin`** :

```powershell
pnpm install
pnpm build
```

**Arrêter l'aperçu avant** (`demarrer.ps1 -Stop`) : reconstruire le back-office pendant qu'il tourne
le casse (erreurs 500) jusqu'au prochain démarrage.

### 3. Construire les apps mobiles en version web

Depuis **`mobile\apps\buyer`**, puis `mobile\apps\seller`, `mobile\apps\driver` et `mobile\apps\pharmacy`
(la même commande dans chacun des 4 dossiers) :

```powershell
flutter build web --profile --no-web-resources-cdn --dart-define=API_BASE_URL=http://localhost:8090 --dart-define=IVIA_DEV_OTP=true --dart-define=IVIA_DEV_PAYMENT=true
```

Compter 5 à 7 minutes par app. Construire une app à la fois : plusieurs en parallèle saturent la
mémoire.

### 4. Remplir la base de démonstration (facultatif)

Les données ne voyagent pas avec Git : chaque poste remplit sa propre base. Docker doit tourner.
Depuis **`backend`** :

```powershell
$env:DATABASE_URL = "postgres://ivia@127.0.0.1:5434/ivia?sslmode=disable"
go run ./cmd/manage seed-demo
```

Compter 2 à 3 minutes. La commande est relançable et ne fonctionne qu'en local.

### 5. Démarrer

Comme au quotidien : `powershell -File tools\preview\demarrer.ps1` depuis la **racine**.

## Après une modification du code

| Ce qui a changé | À refaire |
| --- | --- |
| `backend` | Étape 1, puis redémarrer l'aperçu (`-Stop`, puis démarrer) |
| `admin` | Arrêter l'aperçu, étape 2, puis démarrer |
| Une app de `mobile` | Étape 3 pour cette app seulement ; recharger la page, sans redémarrer |

## Se connecter en local

- **Apps mobiles** : un numéro de démonstration (en 9x ou 7x) ; le code se remplit tout seul. Aucun
  vrai SMS ni WhatsApp n'est envoyé.
- **Paiements** : validés par un faux prestataire, sans aucun vrai paiement.
- **Back-office** : compte `admin@ivia.local`, avec le mot de passe de démonstration de l'équipe (il
  n'est pas écrit ici).
- **E-mails** : tous arrivent dans Mailpit (http://localhost:8025), aucun ne part vraiment.

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| Aucune adresse ne répond | Docker Desktop n'est pas prêt : attendre « Engine running », puis relancer `demarrer.ps1` |
| Docker reste bloqué sur « Starting » | Quitter Docker Desktop (clic droit sur l'icône près de l'horloge › Quit), taper `wsl --shutdown` dans PowerShell, rouvrir Docker Desktop. Si ça ne suffit pas : redémarrer le PC |
| Back-office en erreur 500 | Il a été reconstruit pendant qu'il tournait : `demarrer.ps1 -Stop`, refaire l'étape 2, redémarrer |
| Une app montre une ancienne version | Recharger la page ; sinon l'ouvrir dans une fenêtre de navigation privée |
| Le port 5432 est refusé par Windows | Normal : le projet utilise le port 5434 pour PostgreSQL, déjà réglé dans le script |

## Carte : itinéraires réels (facultatif, gourmand en mémoire)

Sans réglage, les trajets sont estimés à vol d'oiseau. Pour de vrais itinéraires (OSRM), il faut
préparer les données une fois, depuis la **racine**, dans **Git Bash** :

```bash
bash tools/geo/preparer-osrm.sh
```

Le script télécharge environ 60 Mo puis les prépare. **Le lancer seul, sans compilation en cours** :
il a déjà fait planter Docker par manque de mémoire. Une fois les données prêtes, `demarrer.ps1`
lance OSRM tout seul. Détails : [docs/mise-en-service-carte.md](docs/mise-en-service-carte.md).
