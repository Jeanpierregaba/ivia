#!/usr/bin/env bash
# Télécharge l'extrait OSM du Togo et prépare les données d'OSRM (algorithme MLD).
# À relancer chaque semaine : la préparation se fait dans un dossier à part, puis bascule.
# Usage : tools/geo/preparer-osrm.sh
set -euo pipefail

# pwd -W : chemin Windows sous Git Bash, seul accepté par Docker Desktop.
racine="$(cd "$(dirname "$0")/../.." && (pwd -W 2>/dev/null || pwd))"
donnees="$racine/geo-data/osrm-car"
nouveau="$racine/geo-data/osrm-car.nouveau"
image="ghcr.io/project-osrm/osrm-backend:v6.0.0"
extrait="togo-latest.osm.pbf"

rm -rf "$nouveau"
mkdir -p "$nouveau"
curl -fL --retry 3 -o "$nouveau/$extrait" "https://download.geofabrik.de/africa/$extrait"

# MSYS_NO_PATHCONV : Git Bash sous Windows ne doit pas réécrire les chemins du conteneur.
lance() { MSYS_NO_PATHCONV=1 docker run --rm -v "$nouveau:/data" "$image" "$@"; }
lance osrm-extract -p /opt/car.lua "/data/$extrait"
lance osrm-partition /data/togo-latest.osrm
lance osrm-customize /data/togo-latest.osrm
rm -f "$nouveau/$extrait"

rm -rf "$donnees"
mv "$nouveau" "$donnees"
echo "Données prêtes : docker compose --profile geo up -d osrm-car"
