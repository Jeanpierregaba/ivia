#!/usr/bin/env python3
"""Exporte les lieux OSM du Togo en CSV, pour `manage import-places`.

Usage : python tools/geo/osm_pois.py places.csv

À lancer ponctuellement : l'API Overpass est un service public partagé. Données © les contributeurs
d'OpenStreetMap, licence ODbL : mention à garder dans les mentions légales.
"""
import csv
import json
import sys
import urllib.parse
import urllib.request

FILTERS = {
    'market': '["amenity"="marketplace"]',
    'station': '["amenity"="bus_station"]',
    'fuel': '["amenity"="fuel"]',
    'hospital': '["amenity"~"^(hospital|clinic)$"]',
    'pharmacy': '["amenity"="pharmacy"]',
    'bank': '["amenity"="bank"]',
    'school': '["amenity"~"^(university|college)$"]',
    'worship': '["amenity"="place_of_worship"]["name"]',
    'hotel': '["tourism"="hotel"]',
    'mall': '["shop"~"^(mall|supermarket)$"]',
    'airport': '["aeroway"="aerodrome"]',
}


def main(path):
    parts = ''.join(f'nwr{f}["name"](area.togo);' for f in FILTERS.values())
    query = f'[out:json][timeout:120];area["ISO3166-1"="TG"]["admin_level"="2"]->.togo;({parts});out center tags;'
    req = urllib.request.Request(
        'https://overpass-api.de/api/interpreter',
        data=urllib.parse.urlencode({'data': query}).encode(),
        headers={'User-Agent': 'ivia-import-lieux/1.0'},
    )
    with urllib.request.urlopen(req, timeout=180) as res:
        elements = json.load(res)['elements']
    rows = []
    for e in elements:
        tags = e.get('tags', {})
        lat = e.get('lat') or e.get('center', {}).get('lat')
        lng = e.get('lon') or e.get('center', {}).get('lon')
        if lat is None or lng is None or not tags.get('name'):
            continue
        category = next((c for c, f in FILTERS.items() if matches(f, tags)), 'other')
        address = ', '.join(v for v in (tags.get('addr:street'), tags.get('addr:suburb'), tags.get('addr:city')) if v)
        aliases = ';'.join(v for k, v in tags.items() if k in ('alt_name', 'short_name', 'loc_name', 'official_name'))
        rows.append([f"{e['type']}/{e['id']}", tags['name'], category, f'{lat:.6f}', f'{lng:.6f}', address, aliases])
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['external_id', 'name', 'category', 'lat', 'lng', 'address', 'aliases'])
        w.writerows(rows)
    print(f'{len(rows)} lieux écrits dans {path}')


def matches(filter_text, tags):
    import re
    for key, op, value in re.findall(r'\["([^"]+)"(=|~)?"?([^"\]]*)"?\]', filter_text):
        if key not in tags:
            return False
        if op == '=' and tags[key] != value:
            return False
        if op == '~' and not re.search(value, tags[key]):
            return False
    return True


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
