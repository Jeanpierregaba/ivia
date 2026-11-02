# 028 — Pièces du marchand

## Objectif

Permettre au marchand de **déposer sa pièce d'identité** (obligatoire) et son **registre du
commerce** (facultatif) depuis l'app marchand, pour que l'équipe ivia puisse publier sa boutique
([PRD](../../PRD.md) : « l'admin vérifie d'abord la pièce d'identité du marchand »). Suite de
[004](../004-espace-marchand/spec.md) (« 004 bis » dans `TASKS.md`).

Le serveur et le back-office sont faits (Gedeon, 2026-11-02) : sans pièce d'identité, l'admin ne
peut pas publier (409 `merchant_documents_missing`). Aujourd'hui, une boutique créée depuis l'app
reste donc bloquée « en validation ». Pas de maquette : l'écran reprend les lignes de document du
dossier livreur ([018](../018-espace-livreur/spec.md)), aux couleurs de l'app marchand.

## Comportement attendu

**1. Écran « Vérifions votre identité »**, ouvert juste après « Envoyer pour validation » de
« Créez votre boutique ».
- Texte : « L'équipe ivia vérifie votre identité avant de publier votre boutique. Vos pièces ne
  sont vues que par l'équipe ivia. »
- **Pièce d'identité** · « Obligatoire » : « Carte d'identité, passeport ou carte d'électeur, face
  avec la photo ».
- **Registre du commerce (RCCM)** · « Facultatif ».
- Chaque ligne : « Ajouter », qui propose de prendre une photo ou d'en choisir une. Ensuite
  « Ajoutée » (photo choisie, à envoyer) ou « Envoyée » (déjà reçue par le serveur ; un appui
  permet d'en envoyer une nouvelle).
- **« Envoyer mes pièces »** : envoie les photos choisies, puis ouvre « Votre boutique est en cours
  de validation » avec « Pièces envoyées. ». Il faut une pièce d'identité, choisie ou déjà
  envoyée.
- Retour : à l'écran « en cours de validation », sans rien envoyer.

**2. « Votre boutique est en cours de validation »** : une étape de plus.
- Compte créé ✓ · Boutique envoyée ✓ (nom · quartier) · **Pièce d'identité** · Validation par
  ivia · Boutique visible des acheteurs.
- **Pièce manquante** : l'étape « Pièce d'identité » est en cours (« À ajouter : sans elle, la
  boutique ne peut pas être publiée »), « Validation par ivia » est à venir. Le bouton principal
  devient **« Ajouter ma pièce d'identité »** (écran 1) ; « Préparer mes produits » reste
  disponible.
- **Pièce envoyée** : l'étape est faite (« Envoyée ») et la validation est en cours, comme
  aujourd'hui.
- Une boutique déjà en attente sans pièce, créée avant cet écran, suit le même chemin.
- Les pièces sont relues avec la boutique : à l'ouverture de l'app et en tirant vers le bas.

## Critères d'acceptation

- [ ] Étant donné « Créez votre boutique » rempli, quand le marchand envoie, alors la boutique est
      créée et « Vérifions votre identité » s'ouvre, avec la pièce d'identité obligatoire et le
      RCCM facultatif.
- [ ] Étant donné l'écran des pièces sans pièce d'identité, quand le marchand appuie sur « Envoyer
      mes pièces », alors « Ajoutez votre pièce d'identité. » s'affiche et rien n'est envoyé.
- [ ] Étant donné une photo de pièce d'identité choisie (et un RCCM facultatif), quand le marchand
      envoie, alors chaque photo part sur son URL signée (`POST /v1/uploads`, `merchant_document`,
      `image/jpeg`), puis est rattachée (`POST /v1/seller/documents`, `id_card` ou
      `business_registration`), et l'écran « en cours de validation » montre la pièce envoyée.
- [ ] Étant donné une boutique en attente sans pièce d'identité, à l'ouverture de l'app, alors
      l'écran « en cours de validation » montre « Pièce d'identité · À ajouter » et « Ajouter ma
      pièce d'identité ».
- [ ] Étant donné une pièce d'identité déjà envoyée, alors l'étape est faite et l'écran des pièces
      la montre « Envoyée ».

## Cas limites et erreurs

- **Réseau coupé pendant l'envoi** : message, photos gardées ; au nouvel essai, une photo déjà
  envoyée n'est pas renvoyée et une pièce déjà rattachée ne l'est pas deux fois.
- **Photo trop lourde** (plus de 5 Mo après réduction) : refusée dès le choix, comme pour le
  livreur.
- **Trop de pièces** (`too_many_documents`, 10 au plus) : message du serveur.
- **Appareil photo ou galerie refusés** : message, comme pour le livreur.
- **Double appui sur « Envoyer mes pièces »** : un seul envoi. Retour bloqué pendant l'envoi.
- **Boutique lue sans ses pièces** (réponse sans `merchant_documents`) : l'étape « Pièce
  d'identité » n'est pas affichée, le reste de l'écran est inchangé ; tirer vers le bas relit.
- **Marchand qui a déjà déposé sa pièce d'identité** (autre boutique) : après la création, l'écran
  en attente s'ouvre directement.
- **Boutique publiée, refusée ou suspendue** : l'écran des pièces n'est pas proposé.
- **Police à 200 %, écran de 320 dp** : rien n'est masqué.

## Hors périmètre

- Choisir un fichier PDF ; recto et verso de la pièce.
- Voir ou supprimer une pièce envoyée (l'app ne reçoit pas de lien de lecture).
- Pièces demandées pour une boutique déjà publiée, ou après un refus : l'admin le dit dans le
  motif.
- Notification de la publication (012).

## Questions ouvertes

<!-- Vide = prêt pour le plan. -->
