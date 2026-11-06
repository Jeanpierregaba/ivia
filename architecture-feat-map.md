# Architecture — Feature Carte & Géolocalisation (Ivia)

> Document de référence pour l'implémentation de la couche cartographique d'Ivia (VTC, coursier, e-commerce, pharmacies de garde, événements).
> Destinataire : Claude Code / équipe technique.
> Marché de lancement : Togo (Lomé), puis expansion sous-régionale (Afrique de l'Ouest).

---

## 1. Principe directeur : architecture hybride

On ne choisit pas entre Google Maps et OpenStreetMap : **chaque fournisseur est utilisé là où il est le meilleur rapport qualité/coût.**

| Besoin | Solution retenue | Justification |
|---|---|---|
| Affichage de la carte (apps client & chauffeur) | **Google Maps SDK** (Android/iOS via Flutter) | Gratuit et illimité sur mobile, rendu familier |
| Autocomplétion / recherche d'adresse | **Base de lieux Ivia** d'abord → **Google Places API (New)** en secours | Meilleure couverture POI à Lomé, coût maîtrisé par le cache |
| Géocodage inverse (épingle → adresse) | **Nominatim auto-hébergé (OSM)** | Gratuit, appelé très souvent |
| Itinéraires, ETA, distances, matrices | **OSRM auto-hébergé (OSM)** | Gratuit, illimité, latence en ms → indispensable pour le matching |
| Distance réelle parcourue (facturation) | **OSRM `/match`** (map-matching de la trace GPS) | Calcul fiable sans coût externe |
| Positions chauffeurs/coursiers temps réel | **Redis GEO** | Recherche de proximité ultra rapide |
| Lieux métier (pharmacies, boutiques, événements, POI) | **PostgreSQL + PostGIS** | Ce sont nos données, requêtes spatiales natives |
| Navigation guidée du chauffeur | **Deep link Google Maps / Waze** | Pas de Navigation SDK payant en V1 |

**Règle d'or : les apps mobiles n'appellent JAMAIS directement un fournisseur de routage ou de géocodage.** Tout passe par le `GeoService` du backend. Seul l'affichage de la carte (SDK) est côté client.

---

## 2. Vue d'ensemble

```
┌───────────────────┐      ┌───────────────────┐      ┌──────────────────┐
│ App Client        │      │ App Chauffeur /   │      │ Dashboards web   │
│ (Flutter)         │      │ Coursier (Flutter)│      │ (Next.js)        │
│ Google Maps SDK   │      │ Google Maps SDK   │      │ Google Maps JS*  │
└────────┬──────────┘      └────────┬──────────┘      └────────┬─────────┘
         │ REST                     │ REST + WebSocket          │ REST
         └──────────────┬───────────┴───────────────────────────┘
                        ▼
              ┌─────────────────────┐
              │   API Backend       │
              │  ┌───────────────┐  │
              │  │  GeoService   │  │  ← façade unique, interfaces + adapters
              │  └──────┬────────┘  │
              └─────────┼───────────┘
     ┌──────────┬───────┼──────────┬──────────────┬──────────────┐
     ▼          ▼       ▼          ▼              ▼              ▼
 ┌───────┐ ┌─────────┐ ┌───────┐ ┌──────────┐ ┌──────────────┐ ┌────────┐
 │ OSRM  │ │Nominatim│ │ Redis │ │PostgreSQL│ │Google Places │ │ Cache  │
 │(OSM)  │ │ (OSM)   │ │  GEO  │ │+ PostGIS │ │  API (New)   │ │ Redis  │
 └───────┘ └─────────┘ └───────┘ └──────────┘ └──────────────┘ └────────┘
   auto-hébergés                                  externe, payant
```

\* Dashboards web : la Maps JavaScript API (Dynamic Maps) est facturée au chargement au-delà du quota gratuit. Volume faible (admins, boutiques) → acceptable. Alternative : MapLibre GL + tuiles OSM d'un fournisseur.

---

## 3. Le `GeoService` (cœur de l'architecture)

### 3.1 Principe

Pattern **Port / Adapter** : le code métier (matching, tarification, livraison) dépend d'interfaces, jamais d'un fournisseur. Changer de fournisseur = changer d'adapter via configuration.

### 3.2 Interfaces (pseudo-code, à transposer dans le langage du backend)

```text
interface RoutingProvider {
  route(origin: LatLng, destination: LatLng, waypoints?: LatLng[]) -> Route
      // Route { distanceMeters, durationSeconds, polyline (polyline6) }
  matrix(sources: LatLng[], destinations: LatLng[]) -> Matrix
      // Matrix { durations[][], distances[][] }
  matchTrace(points: GpsPoint[]) -> MatchedTrace
      // MatchedTrace { distanceMeters, durationSeconds, polyline, confidence }
}

interface GeocodingProvider {
  reverse(position: LatLng) -> Address
}

interface PlaceSearchProvider {
  autocomplete(query: string, near: LatLng, sessionToken: string) -> PlaceSuggestion[]
  details(placeId: string, sessionToken: string) -> Place
}

interface DriverLocationStore {
  upsert(driverId, position: LatLng, heading, speed, status, vehicleType)
  nearby(position: LatLng, radiusMeters, filters, limit) -> DriverCandidate[]
  remove(driverId)
}
```

### 3.3 Adapters à implémenter

| Interface | Adapter V1 | Adapter alternatif (prévu, pas en V1) |
|---|---|---|
| `RoutingProvider` | `OsrmRoutingAdapter` | `GoogleRoutesAdapter` (fallback/benchmark) |
| `GeocodingProvider` | `NominatimGeocodingAdapter` | `GoogleGeocodingAdapter` |
| `PlaceSearchProvider` | `CompositePlaceSearch` (Ivia DB → Google Places) | `PhotonPlaceSearchAdapter` (100 % OSM) |
| `DriverLocationStore` | `RedisGeoDriverStore` | — |

Le choix des adapters se fait **par configuration** (variables d'environnement), par ex. :
```
GEO_ROUTING_PROVIDER=osrm
GEO_GEOCODING_PROVIDER=nominatim
GEO_PLACES_PROVIDER=composite   # composite | google | photon
```

### 3.4 Résilience

- Timeouts courts (OSRM : 500 ms ; Google : 2 s), retries limités.
- Circuit breaker sur chaque provider externe.
- Si OSRM est indisponible : fallback temporaire sur estimation à vol d'oiseau (Haversine × coefficient de détour ≈ 1,3) pour le matching, et alerte monitoring. Ne **jamais** basculer automatiquement sur Google Routes (risque de facture).

---

## 4. Composants détaillés

### 4.1 OSRM — routage, ETA, matrices, map-matching

- Image Docker : `osrm/osrm-backend`.
- Données : extrait Geofabrik `africa/togo-latest.osm.pbf` (puis extraits des pays d'expansion, ou `africa/` filtré par zone).
- Profil : `car.lua` (VTC). Prévoir un second instance avec un profil moto (`bicycle.lua` adapté ou profil custom) si le module coursier utilise des motos (zémidjans), car les vitesses et accès diffèrent.
- Algorithme : **MLD** (permet des mises à jour de données plus rapides que CH).

Préparation des données :
```bash
osrm-extract   -p /opt/car.lua /data/togo-latest.osm.pbf
osrm-partition /data/togo-latest.osrm
osrm-customize /data/togo-latest.osrm
osrm-routed --algorithm mld /data/togo-latest.osrm
```

Services utilisés :
| Service | Usage Ivia |
|---|---|
| `/route/v1/driving/{lon,lat;lon,lat}?overview=full&geometries=polyline6` | Itinéraire + estimation de prix + tracé à afficher |
| `/table/v1/driving/{coords}?sources=...&destinations=...&annotations=duration,distance` | Matching : ETA de N chauffeurs vers le client en 1 appel |
| `/match/v1/driving/{coords}?timestamps=...&radiuses=...` | Distance réellement parcourue (facturation finale, litiges) |

⚠️ OSRM attend les coordonnées en **`longitude,latitude`** (ordre inverse de Google). Centraliser la conversion dans l'adapter.

Mise à jour des données : job planifié (hebdomadaire) qui télécharge le nouvel extrait, reconstruit dans un répertoire séparé, puis bascule (blue/green) sans interruption.

### 4.2 Nominatim — géocodage inverse

- Image Docker : `mediagis/nominatim`, importé avec l'extrait Togo.
- Usage : quand l'utilisateur déplace l'épingle sur la carte → `GET /reverse?format=jsonv2&lat=..&lon=..`.
- Résultat mis en cache Redis (clé = coordonnées arrondies à ~4 décimales, TTL 30 jours).
- Le libellé affiché doit privilégier : POI Ivia proche (< 50 m) > nom de rue/quartier Nominatim > coordonnées.

### 4.3 Recherche de lieux — `CompositePlaceSearch`

Ordre de résolution d'une recherche :

1. **Lieux personnels** de l'utilisateur (Maison, Travail, favoris, 10 dernières destinations).
2. **Base de lieux Ivia** (table `places`, PostGIS + recherche plein texte / trigram) : marchés, gares routières, hôtels, hôpitaux, pharmacies, boutiques partenaires, lieux d'événements, points de prise en charge fréquents.
3. **Google Places API (New)** uniquement si les étapes 1-2 renvoient moins de N résultats pertinents (N configurable, ex. 3).

Règles d'appel Google :
- Côté app : **debounce 300-400 ms** et **minimum 3 caractères** avant d'appeler le backend.
- **Session token** obligatoire (un token par session de recherche, réutilisé dans l'appel `details` final).
- Autocomplete : `POST https://places.googleapis.com/v1/places:autocomplete` avec `locationBias` centré sur la position de l'utilisateur et `includedRegionCodes` = pays actif (`tg`).
- Details : `GET https://places.googleapis.com/v1/places/{placeId}` avec un **`X-Goog-FieldMask` minimal** (`id,displayName,formattedAddress,location`). Le field mask détermine le SKU facturé : ne jamais demander plus que nécessaire.
- **Apprentissage** : chaque lieu Google sélectionné par un utilisateur est enregistré dans la table `places` (source = `google`, compteur d'usage). La base Ivia s'enrichit avec le temps et les appels Google diminuent.
- Vérifier dans la doc Google à jour les règles de facturation des sessions et les conditions de stockage des données Places (durée de conservation autorisée des `place_id` / coordonnées) avant la mise en production.

### 4.4 Positions temps réel — Redis GEO

- Les apps chauffeur/coursier envoient leur position via **WebSocket** toutes les **3 à 5 s** quand elles sont en ligne (toutes les 10-15 s si immobiles, pour économiser batterie et data).
- Payload : `{ lat, lng, heading, speed, accuracy, timestamp }`.
- Stockage :
  - `GEOADD drivers:{city}:{vehicleType} lng lat driverId`
  - Hash `driver:{id}` : statut (`available`, `busy`, `offline`), dernier timestamp, etc.
  - Expiration : un chauffeur sans mise à jour depuis 60 s est considéré hors ligne (job de nettoyage ou vérification du timestamp au moment du matching).
- Recherche : `GEOSEARCH drivers:lome:car FROMLONLAT lng lat BYRADIUS 3 km ASC COUNT 20`.
- Pendant une course : diffusion de la position du chauffeur au client via WebSocket (canal par course), et ajout des points GPS à la trace de la course (bufferisés, persistés par lots dans PostgreSQL).

### 4.5 PostgreSQL + PostGIS — données géographiques métier

Tables principales (indicatives) :

```sql
-- Lieux connus (POI Ivia + lieux appris via Google)
CREATE TABLE places (
  id            UUID PRIMARY KEY,
  name          TEXT NOT NULL,
  aliases       TEXT[],                 -- noms locaux ("Grand Marché", "Assigamé")
  category      TEXT,                   -- market, station, hotel, pharmacy, shop, event_venue...
  address_label TEXT,
  location      GEOGRAPHY(Point, 4326) NOT NULL,
  country_code  CHAR(2) NOT NULL,
  source        TEXT NOT NULL,          -- ivia | google | osm | user
  external_id   TEXT,                   -- place_id Google si applicable
  usage_count   INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX places_location_gix ON places USING GIST (location);
CREATE INDEX places_name_trgm    ON places USING GIN (name gin_trgm_ops);

-- Lieux personnels des utilisateurs
CREATE TABLE user_places (
  id        UUID PRIMARY KEY,
  user_id   UUID NOT NULL,
  label     TEXT NOT NULL,              -- "Maison", "Travail", libre
  type      TEXT NOT NULL,              -- home | work | favorite | recent
  location  GEOGRAPHY(Point, 4326) NOT NULL,
  address_label TEXT,
  last_used_at TIMESTAMPTZ
);

-- Pharmacies (module e-médecine)
CREATE TABLE pharmacies (
  id        UUID PRIMARY KEY,
  name      TEXT NOT NULL,
  location  GEOGRAPHY(Point, 4326) NOT NULL,
  phone     TEXT,
  country_code CHAR(2) NOT NULL
);
CREATE TABLE pharmacy_on_duty (       -- pharmacies de garde par période
  pharmacy_id UUID REFERENCES pharmacies(id),
  starts_at   TIMESTAMPTZ NOT NULL,
  ends_at     TIMESTAMPTZ NOT NULL
);

-- Zones (tarification, zones desservies, surge)
CREATE TABLE zones (
  id        UUID PRIMARY KEY,
  name      TEXT NOT NULL,
  type      TEXT NOT NULL,              -- service_area | pricing | surge | airport
  area      GEOGRAPHY(Polygon, 4326) NOT NULL,
  rules     JSONB
);
CREATE INDEX zones_area_gix ON zones USING GIST (area);

-- Trace GPS des courses
CREATE TABLE trip_points (
  trip_id   UUID NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL,
  location  GEOGRAPHY(Point, 4326) NOT NULL,
  speed     REAL,
  heading   REAL
);
```

Exemples d'usage :
- Pharmacies de garde les plus proches : `ST_DWithin` + tri par `ST_Distance`, puis ETA réel via OSRM `/table` sur les 10 premières.
- Vérifier qu'un point de prise en charge est dans la zone desservie : `ST_Covers(zones.area, point)`.

---

## 5. Flux métier

### 5.1 Estimation de prix (avant commande)

1. Client choisit départ + destination (via `CompositePlaceSearch` ou épingle + Nominatim).
2. Backend → `RoutingProvider.route(origin, destination)`.
3. Calcul : `prix = base + (km × tarif_km) + (min × tarif_min)`, ajusté par zone (`zones.rules`) et multiplicateur de demande éventuel.
4. Retour au client : prix (ou fourchette), durée, tracé polyline à afficher.
5. Mettre en cache l'estimation (clé = origine/destination arrondies + type de véhicule, TTL court ~5 min).

### 5.2 Matching chauffeur

1. `DriverLocationStore.nearby(pickup, 3 km, {status: available, vehicleType}, 20)`.
2. Si 0 résultat : élargir le rayon par paliers (5 km, 8 km), puis informer le client.
3. `RoutingProvider.matrix(sources = positions des candidats, destinations = [pickup])` → ETA réels en **un seul appel**.
4. Classement : ETA, puis note, taux d'acceptation, etc.
5. Dispatch séquentiel ou par lots (offre envoyée au meilleur, timeout 15 s, puis suivant).

### 5.3 Course en cours

1. Chauffeur accepte → `route(position chauffeur, pickup)` → ETA affiché au client.
2. Navigation : bouton qui ouvre Google Maps / Waze via deep link (`google.navigation:q=lat,lng` sur Android, URL universelle `https://www.google.com/maps/dir/?api=1&destination=lat,lng`).
3. Positions chauffeur → Redis + WebSocket client + buffer `trip_points`.
4. Recalcul d'ETA côté backend toutes les 30-60 s (pas à chaque point GPS).

### 5.4 Fin de course et facturation

1. `RoutingProvider.matchTrace(trip_points)` → distance et durée réelles.
2. Prix final = prix fixe annoncé (si tarification fixe) ou recalcul sur distance réelle (si tarification dynamique). Garder la trace pour la gestion des litiges.

### 5.5 Coursier / livraison e-commerce

Même logique que le VTC, avec :
- Profil de routage adapté au véhicule (moto vs voiture).
- Itinéraires multi-points (`waypoints`) : boutique → client, ou tournées.

---

## 6. Côté application mobile (Flutter)

- Package carte : `google_maps_flutter`.
- Clés API Google **restreintes** : une clé Android (restreinte par package + SHA-1), une clé iOS (restreinte par bundle ID), activées uniquement sur Maps SDK. **Aucune** clé Places/Routes dans l'app : ces appels passent par le backend (clé serveur, restreinte par IP).
- Sélection d'adresse :
  - Champ de recherche → endpoint backend `/geo/places/autocomplete` (debounce 300-400 ms, min 3 caractères, session token généré côté app et transmis).
  - Mode « déplacer l'épingle » → endpoint `/geo/reverse` à l'arrêt du mouvement de carte (pas pendant le déplacement).
  - Accès rapide aux lieux personnels et récents en tête de liste.
- Affichage du tracé : décoder la polyline6 renvoyée par le backend.
- Lissage du marqueur chauffeur : interpolation animée entre deux positions reçues.

### Endpoints backend exposés aux apps

| Méthode | Endpoint | Rôle |
|---|---|---|
| GET | `/geo/places/autocomplete?q=&lat=&lng=&session=` | Recherche composite |
| GET | `/geo/places/{id}?session=` | Détails d'un lieu (Ivia ou Google) |
| GET | `/geo/reverse?lat=&lng=` | Adresse d'une position |
| POST | `/geo/route` | Itinéraire + distance + durée |
| POST | `/rides/estimate` | Estimation de prix |
| WS | `/ws/driver/location` | Flux de positions chauffeur |
| WS | `/ws/rides/{id}/tracking` | Suivi de course côté client |

---

## 7. Infrastructure

`docker-compose` de développement (à adapter pour la prod) :

```yaml
services:
  osrm-car:
    image: osrm/osrm-backend
    command: osrm-routed --algorithm mld /data/togo-latest.osrm
    volumes:
      - ./geo-data/osrm-car:/data
    ports: ["5000:5000"]

  nominatim:
    image: mediagis/nominatim
    environment:
      PBF_URL: https://download.geofabrik.de/africa/togo-latest.osm.pbf
    volumes:
      - nominatim-data:/var/lib/postgresql
    ports: ["8080:8080"]

  redis:
    image: redis:7
    ports: ["6379:6379"]

  postgres:
    image: postgis/postgis:16-3.4
    environment:
      POSTGRES_PASSWORD: change-me
    volumes:
      - pg-data:/var/lib/postgresql/data
    ports: ["5432:5432"]

volumes:
  nominatim-data:
  pg-data:
```

Dimensionnement indicatif (Togo seul) : OSRM + Nominatim tiennent sur un VPS de 8 Go de RAM. Pour plusieurs pays de la sous-région, prévoir 16 Go et réévaluer. OSRM et Nominatim ne doivent **pas** être exposés publiquement (réseau privé, accessibles uniquement par le backend).

---

## 8. Maîtrise des coûts Google

- Dans la console Google Cloud : **quotas journaliers plafonnés** par API (Places, Geocoding) et **alertes budgétaires** (50 %, 80 %, 100 %).
- APIs activées sur le projet : uniquement Maps SDK for Android, Maps SDK for iOS, Places API (New), et Maps JavaScript API si les dashboards l'utilisent. Routes API et Geocoding API **non activées** en V1.
- Métriques internes à suivre (dashboard admin) :
  - nombre d'appels Google Places / jour ;
  - **taux de résolution locale** = recherches résolues par la base Ivia ou les lieux personnels / total des recherches (objectif : > 70 % après quelques mois) ;
  - taux de hit du cache de géocodage inverse.
- Plan B documenté : si la facture Places devient gênante, passer `GEO_PLACES_PROVIDER=photon` (Photon auto-hébergé sur OSM) sans modifier les apps.

---

## 9. Expansion multi-pays

- Chaque entité géographique porte un `country_code`.
- OSRM/Nominatim : ajouter l'extrait Geofabrik du pays (ou fusionner les extraits avec `osmium merge`) puis reconstruire.
- Clés Redis GEO partitionnées par ville (`drivers:{city}:{vehicleType}`).
- Tarification et zones configurées par ville dans `zones`.
- Google Places : `includedRegionCodes` = pays de l'utilisateur.

---

## 10. Plan d'implémentation

| Phase | Contenu | Critères d'acceptation |
|---|---|---|
| **1. Socle** | docker-compose (OSRM, Nominatim, Redis, PostGIS), interfaces `GeoService`, adapters OSRM + Nominatim | `route`, `matrix`, `reverse` fonctionnels sur Lomé avec tests d'intégration |
| **2. Validation terrain** | Script de benchmark : 20-30 trajets réels à Lomé comparés OSRM vs Google (distance, durée) | Écart moyen documenté ; décision go/no-go sur OSRM, corrections OSM éventuelles |
| **3. Recherche de lieux** | Tables `places` / `user_places`, `CompositePlaceSearch`, adapter Google Places (session tokens, field mask), apprentissage des lieux | Recherche fonctionnelle ; Google appelé seulement en secours ; lieux sélectionnés persistés |
| **4. Temps réel** | WebSocket positions, `RedisGeoDriverStore`, expiration des chauffeurs inactifs | 500 chauffeurs simulés envoyant une position toutes les 3 s sans dégradation |
| **5. Matching & prix** | Estimation de prix, matching via `/table`, dispatch | Estimation < 300 ms ; matching (recherche + matrice) < 500 ms |
| **6. Course & facturation** | Suivi en direct, trace GPS, `/match` en fin de course, deep links navigation | Distance facturée cohérente avec le trajet réel |
| **7. Observabilité & coûts** | Métriques (appels Google, taux de résolution locale, latences OSRM), alertes, quotas Google | Dashboard opérationnel ; alertes budgétaires configurées |
| **8. Données Ivia** | Import initial des POI (marchés, gares, hôtels, pharmacies…), back-office d'administration des lieux et zones | Base initiale chargée et éditable depuis le dashboard admin |

---

## 11. Points d'attention

- **Ordre des coordonnées** : OSRM = `lon,lat` ; Google = `lat,lng`. Utiliser un type `LatLng` unique dans le code et convertir uniquement dans les adapters.
- **Politique d'usage OSM** : ne jamais utiliser les serveurs publics `openstreetmap.org` / `nominatim.openstreetmap.org` en production. Tout est auto-hébergé.
- **Attribution** : afficher « © OpenStreetMap contributors » là où des données OSM sont présentées (ex. page « À propos » / mentions légales), conformément à la licence ODbL.
- **Conditions Google** : respecter les règles de stockage des données Places et l'obligation d'afficher les résultats Places en lien avec une carte Google ou avec l'attribution requise. Vérifier les CGU à jour.
- **Vie privée** : positions et traces GPS = données personnelles. Définir une durée de rétention (ex. traces détaillées conservées X mois puis agrégées) et chiffrer les sauvegardes.
- **Batterie / data** : fréquence d'envoi GPS adaptative selon le mouvement et l'état (en course / disponible).
