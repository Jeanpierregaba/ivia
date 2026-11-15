# 037 — Messagerie de la course

<!-- Demandé le 2026-11-13 ; spec écrite avec le code. -->

## Objectif
Une mini messagerie, façon WhatsApp, entre le client et le livreur, et entre le livreur et la
boutique, dès qu'une course est acceptée.

## Comportement
- Deux fils par commande : client ↔ livreur, livreur ↔ boutique. Le client ne voit jamais le fil
  de la boutique, et inversement.
- Ouverts dès qu'un livreur a accepté la course ; en lecture seule une fois la course terminée.
- Bulles, heure, accusés de lecture (✓ envoyé, ✓✓ bleu lu), séparateurs de jour, messages rapides
  selon qui écrit (« J'arrive », « Je suis devant », « La commande est prête »…).
- Nouveau message : reçu en direct (WebSocket), push sur téléphone, bandeau dans l'app qui ouvre la
  discussion (sauf si elle est déjà ouverte).
- Entrées : ivia et Business, « Écrire au livreur » dans le suivi de la livraison ; Livreur,
  « Écrire au client » et « Écrire à la boutique » sur chaque étape de la mission.

## Règles
- Seuls les participants de la commande accèdent au fil (sinon 404).
- 1 à 1 000 caractères ; 30 messages par minute et par compte au plus.
- Les messages ne sont jamais écrits dans les journaux.

## Données et API
Migration 00048 (`chat_messages`, `chat_reads`). Routes : `GET|POST /v1/orders/{id}/chat`,
`GET|POST /v1/seller/orders/{id}/chat`, `GET|POST /v1/driver/orders/{id}/chat/{client|shop}`.
Test : `internal/app/chat_test.go`.
