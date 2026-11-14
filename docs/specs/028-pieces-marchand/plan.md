# 028 — Plan technique

## Approche

- **Aucun changement serveur** (fait par Gedeon, 2026-11-02, migration 00022) :
  - `POST /v1/uploads` `{purpose: "merchant_document", content_type, size_bytes}` → URL signée du
    compartiment privé (rôle `seller` exigé : il existe dès la création de la boutique) ;
  - `POST /v1/seller/documents` `{kind, object_key}` → toutes les pièces et `required` ;
  - `GET /v1/seller/documents` → `items` (`id`, `kind`, `created_at`, sans lien de lecture) et
    `required` (`["id_card"]`).
- **Envoi** comme le dossier livreur : photo choisie (appareil ou galerie, réduite à 2048 px,
  JPEG), puis URL signée, puis rattachement. Les clés déjà envoyées et les pièces déjà rattachées
  sont retenues dans l'écran : un nouvel essai ne refait que ce qui manque.
- **Pièces déjà déposées** : le serveur les joint à chaque boutique du marchand
  (`merchant_documents`, sans lien). L'app les lit donc avec la boutique (`sellerShopProvider` :
  ouverture de l'app, tirer vers le bas), sans appel ni provider de plus ; après un dépôt, la
  boutique gardée prend la liste rendue par `POST /v1/seller/documents`. La pièce d'identité est
  la seule obligatoire (`required`, figé côté app). Le routeur ne dépend pas des pièces : l'écran
  « en cours de validation » les affiche, et l'écran des pièces est une route sous lui. Après la
  création, l'écran des pièces ne s'ouvre que si la pièce d'identité manque (marchand qui en a déjà
  déposé une : écran en attente directement).
- **Ligne de document partagée** : `DocumentRow` du livreur passe dans `app_core`
  (`DocumentPhotoRow` : libellé, aide, mention « Obligatoire » / « Facultatif », photo, déjà
  envoyée) ; le livreur et le marchand l'utilisent.

## Fichiers touchés

**`packages/api_client`**
- `models.dart` : `MerchantDocumentKind` (`idCard`, `businessRegistration`, `other`, `unknown`) ;
  `Shop.merchantDocuments` (`null` si la réponse n'en a pas) et `Shop.withDocuments`.
- `client.dart` : `addMerchantDocument(kind, objectKey)` (rend les types de toutes les pièces).
- `testing.dart` : `FakeMerchantDocuments` (URL signée, fichier réellement envoyé, 10 au plus,
  `required`, refus) ; `shopBody(documents:)`.

**`packages/app_core`**
- `document_photo_row.dart` (déplacé de l'app livreur et rendu générique) ; constante
  `maxUploadBytes`.

**`apps/driver`** : `document_row.dart` supprimé, `DocumentPhotoRow` utilisé directement ;
`requiredDocuments` et `documentLabel` passent dans `dossier_labels.dart` (comportement inchangé).
Un fichier refusé à la transmission (`object_key`) est renvoyé au nouvel essai, comme côté marchand.

**`apps/seller`**
- `app/seller_shop.dart` : `SellerShop.documentsSent(kinds)`.
- `features/shop/shop_documents_screen.dart` (créé) : « Vérifions votre identité ».
- `features/shop/shop_pending_screen.dart` : étape « Pièce d'identité », bouton « Ajouter ma pièce
  d'identité ».
- `features/shop/shop_form_screen.dart` : après la création, ouvre l'écran des pièces.
- `app/router.dart` : `/shop/pending/documents` (le retour mène à l'écran en attente).

**Docs** : `DESIGN.md` (écran des pièces), `TASKS.md`.

## Données

Aucune migration. Rien sur le téléphone : les photos restent en mémoire jusqu'à l'envoi.

## API / interfaces

Voir Approche. Erreurs traitées : `validation_failed` (type, taille), `too_many_documents`,
`forbidden` (rôle), réseau.

## Dépendances

Aucune (sélecteur de photo déjà dans `app_core`).

## Sécurité

- Pièces dans le compartiment privé ; l'app n'en reçoit jamais de lien de lecture.
- Photos réduites et réencodées avant l'envoi (métadonnées, dont la position, retirées par le
  sélecteur existant) ; jamais écrites sur le téléphone ni journalisées.

## Tests

- `api_client` : modèles (types inconnus tolérés, pièces absentes), méthodes, faux serveur.
- `app_core` : `DocumentPhotoRow` (états, sémantique, photo trop lourde).
- App marchand : création puis écran des pièces ; pièce obligatoire ; envoi (URL signée,
  rattachement, types) ; nouvel essai après coupure sans double envoi ; `too_many_documents` ;
  écran en attente avec et sans pièce, boutique sans pièces ; marchand qui a déjà sa pièce ; police à 200 % sur 320 dp.
- App livreur : tests existants inchangés (non-régression de la ligne partagée).

## Risques

- Le déplacement de `DocumentRow` touche l'app livreur : couvert par ses tests existants.
- L'écran en attente reste monté sous l'écran des pièces : il ne relit la boutique au retour dans
  l'app que s'il est visible (l'appareil photo met l'app en pause), et une relecture partie avant
  un dépôt n'écrase pas les pièces rendues par le serveur.
