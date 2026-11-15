# Mise en service de la carte

Décision : `docs/decisions/0013-carte-hybride-geoservice.md`. Référence : `architecture-feat-map.md`.

Sans aucun réglage, tout fonctionne en local sans appel externe payant : itinéraires à vol d'oiseau × 1,3, recherche dans la base Ivia, carte sur les tuiles OpenStreetMap (développement seulement).

## 1. Services auto-hébergés

```bash
tools/geo/preparer-osrm.sh                     # une fois, puis chaque semaine
docker compose --profile geo up -d redis osrm-car nominatim
```

Nominatim importe le Togo au premier démarrage (environ 30 minutes). Ces services demandent 8 Go de RAM au total et ne doivent jamais être exposés publiquement.

Variables du serveur :

```
GEO_ROUTING_PROVIDER=osrm
OSRM_URL=http://127.0.0.1:5000
GEO_GEOCODING_PROVIDER=nominatim
NOMINATIM_URL=http://127.0.0.1:8081
REDIS_URL=redis://127.0.0.1:6379/0
```

## 2. Lieux

```bash
python tools/geo/osm_pois.py places.csv
go run ./cmd/manage import-places places.csv   # relançable, sans doublon
```

Ensuite, Back-office › Lieux pour corriger et ajouter les noms locaux. Données © les contributeurs d'OpenStreetMap : mention à garder dans les mentions légales.

## 3. Tarifs

Back-office › Zones et tarifs. **Sans zone de tarif sur le point de départ, `POST /v1/rides/estimate` refuse de donner un prix** : aucun tarif n'est écrit dans le code. Une zone « Zone desservie » limite les départs possibles dès qu'elle existe.

## 4. Google (clés à créer, jamais dans le dépôt)

1. Console Google Cloud : activer uniquement Maps SDK for Android, Maps SDK for iOS et Places API (New). Laisser Routes API et Geocoding API désactivées.
2. Plafonner les quotas par API et poser des alertes de budget à 50, 80 et 100 %.
3. Clé serveur restreinte par IP : `GOOGLE_PLACES_API_KEY=…` et `GEO_PLACES_PROVIDER=composite`.
4. Clé Android restreinte par package et SHA-1, passée à la compilation :
   `MAPS_API_KEY=… flutter build apk --dart-define=IVIA_GOOGLE_MAPS=true`
5. Clé iOS restreinte par bundle : `GMSServices.provideAPIKey(...)` à ajouter dans `ios/Runner/AppDelegate.swift` de chaque app.

Avant d'activer Places : vérifier dans les conditions Google la durée de conservation autorisée, car les lieux choisis sont gardés dans la table `places`.

## 5. Avant la production

- **Identifiants Android :** `com.example.ivia_buyer` et `com.example.ivia_driver` sont encore les valeurs par défaut. Une clé Android se restreint par package : à changer avant de créer les clés.
- **Tuiles :** définir `IVIA_GOOGLE_MAPS=true` partout. Le serveur public de tuiles OpenStreetMap est interdit en production.
- **Mesure terrain (phase 2 du document) :** comparer 20 à 30 trajets réels à Lomé entre OSRM et Google, pour décider de garder OSRM et corriger OSM si besoin.
- **Profil moto :** sans `OSRM_MOTO_URL`, les motos utilisent les temps de la voiture.
