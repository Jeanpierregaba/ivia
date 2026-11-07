# 032 — Pharmacie : manques côté serveur et paiement en espèces par le livreur

## Objectif

La spec 031 a habillé l'app pharmacie d'après les maquettes. Certains éléments des maquettes
n'existent pas encore dans l'API ; l'app fait sans en attendant (liste dans `TASKS.md`, « Pharmacie
(031) — manques côté serveur »). Cette spec les ajoute côté serveur, puis branche l'app pharmacie
(et l'app livreur pour la remise) sur ces nouveaux éléments.

Elle change aussi **le paiement des livraisons de médicaments** (décision du porteur du projet,
2026-11-07) :
- Aujourd'hui, le client paie dans l'app et ivia doit reverser plus tard à la pharmacie son dû
  (`pharmacy_due_xof`), sur un compte Mobile Money.
- Désormais, **le livreur paie la pharmacie en espèces au moment du retrait**. Tous les livreurs
  ont de la liquidité pour cela. **Ivia ne verse plus rien aux pharmacies après coup.**
- Le client paie toujours dans l'app. **Ivia rembourse au livreur l'argent avancé**, en plus de
  sa course.

Conséquences : le compte de versement de la pharmacie disparaît (dossier en 4 étapes), le relevé
(F22) devient un historique des encaissements, et la remise au livreur se fait avec son code et
la confirmation du paiement en espèces. Un ADR consigne ce changement.

Le travail est fait côté serveur par Jean-Pierre ; **Gedeon relit les migrations avant fusion**
(règle du projet).

## Comportement attendu

**1. Numéro court d'alerte** : chaque alerte reçoit un numéro « A-1 », « A-2 »… qui ne repasse
jamais par zéro, comme les numéros de commande. La pharmacie le voit dans la boîte, le détail,
l'alerte plein écran, l'historique et « Réponse envoyée ». Le client le voit dans le suivi de son
alerte.

**2. Quartier du client** : l'alerte reçue par la pharmacie indique le quartier du client
(« Tokoin »), le plus proche de la position de l'alerte. Jamais l'adresse ni la position exacte.
Affiché dans l'alerte plein écran et le détail (« Client à 650 m · Tokoin »).

**3. Remise au livreur avec son code** :
- Le livreur, arrivé à la pharmacie, voit dans son app un code de retrait à 4 chiffres.
- La pharmacie saisit ce code sur l'écran de la commande (F17), coche « Le livreur m'a payé
  7 450 F en espèces », puis « Valider la remise ».
- La commande passe « récupérée », comme quand le livreur appuie aujourd'hui sur « Récupéré ».
  Le livreur ne peut plus se déclarer « récupéré » seul : son app attend la validation de la
  pharmacie.
- Un code faux affiche l'erreur et ne change rien. Après plusieurs codes faux, la remise est
  bloquée quelques minutes.

**4. Argent avancé par le livreur** : à la remise, le montant payé par le livreur (le dû de la
pharmacie) est enregistré sur la livraison. Le livreur le voit dans sa mission et son historique
(« Avancé à la pharmacie : 7 450 F, remboursé par ivia avec la course »). L'équipe ivia le voit au
back-office, dans la livraison.

**5. Heure d'arrivée et heure de récupération du livreur** : la commande vue par la pharmacie
indique, livreur en route, son arrivée estimée en minutes (calculée à partir de sa dernière
position), puis l'heure de récupération une fois la remise validée (F17, F19).

**6. Plus de versement aux pharmacies** :
- Le dossier n'exige plus de compte de versement : l'envoi pour validation ne demande que les
  pièces obligatoires. L'app passe à 4 étapes (fiche, carte, pièces, planning).
- Le relevé (F22) devient « Encaissements » : retraits payés au comptoir et livraisons payées par
  le livreur, groupés par jour, avec le total du jour et de la semaine. Plus de solde « à
  recevoir », plus de période ni de date de versement.
- Les comptes de versement déjà enregistrés restent en base (sans usage), et ne sont plus
  demandés ni affichés.

**7. Forfait remboursé à l'annulation** : la feuille « Annuler cette commande ? » (F18) indique
le montant remboursé au client (« Le client est prévenu et remboursé de son forfait de 100 F »),
tel qu'il est réellement remboursé.

**8. Photo de la devanture** : la pharmacie voit sa photo de devanture en photo de profil (accueil,
profil) et dans sa fiche (étape 1), au lieu de la tuile du logo.

**9. Origine des gardes** : une garde importée depuis une liste porte la mention « planning
officiel » et la date d'import. Le planning (F20) affiche « Garde de nuit · planning officiel » et
la carte « Planning officiel · importé le 1er nov. · prochaine garde le 12 ».

**10. Compteurs du jour** : l'accueil (F09) reçoit du serveur les chiffres du jour (alertes
reçues, répondues, confirmées), calculés sur toutes les alertes du jour à Lomé, et non plus sur les
50 dernières.

**11. Sonnerie coupée sur iPhone** : le téléphone enregistre son choix de sonnerie avec son jeton
de notification. Si la sonnerie est coupée, le serveur envoie l'alerte sans son à ce téléphone ;
sinon, avec le son. Le réglage « Sonnerie des alertes » est alors proposé aussi sur iPhone.

**12. Pièces en PDF** (côté app seulement, le serveur les accepte déjà) : à l'étape des pièces,
« Prendre une photo », « Choisir une photo » et « Choisir un fichier PDF ». Le libellé redevient
« PDF ou photo ».

## Critères d'acceptation

- [ ] Étant donné deux alertes créées l'une après l'autre, alors leurs numéros se suivent
      (« A-n », « A-n+1 ») et figurent dans la boîte et le détail de la pharmacie et dans le suivi
      du client.
- [ ] Étant donné une alerte, alors la pharmacie reçoit le nom du quartier le plus proche, jamais
      la position du client.
- [ ] Étant donné une livraison dont le livreur est arrivé, quand la pharmacie saisit le bon code
      du livreur et coche le paiement, alors la commande passe « récupérée », l'heure de
      récupération et le montant avancé sont enregistrés, et le livreur est prévenu.
- [ ] Étant donné un code faux, alors la remise est refusée avec un message ; après 5 essais
      faux, elle est bloquée 10 minutes.
- [ ] Le livreur ne peut plus déclarer seul une commande de pharmacie « récupérée ».
- [ ] Le livreur voit son code de retrait, puis le montant avancé dans sa mission et son
      historique.
- [ ] Étant donné un livreur en route, alors la commande vue par la pharmacie donne son arrivée
      estimée en minutes.
- [ ] Étant donné un dossier avec les pièces obligatoires et sans compte de versement, quand la
      pharmacie l'envoie, alors il part en validation.
- [ ] Le relevé de la pharmacie liste les encaissements par jour (retraits et livraisons), sans
      solde à recevoir ; l'app l'affiche sous le titre « Encaissements ».
- [ ] La feuille d'annulation affiche le forfait réellement remboursé.
- [ ] La fiche de la pharmacie renvoie un lien signé de courte durée vers la photo de la
      devanture ; l'accueil, le profil et la fiche l'affichent.
- [ ] Une garde importée porte l'origine « planning officiel » et sa date d'import ; une garde
      ajoutée à la main, non.
- [ ] Les compteurs du jour viennent du serveur et comptent toutes les alertes du jour à Lomé.
- [ ] Étant donné un iPhone dont la sonnerie est coupée, alors le push d'alerte part sans son ;
      sur un téléphone où elle est active, avec le son. Le réglage est proposé sur iPhone.
- [ ] À l'étape des pièces, un PDF peut être choisi et envoyé.
- [ ] Chaque nouvelle route ou nouveau champ est décrit dans `openapi.yaml` ; les types de l'app
      sont à jour ; les tests Go et Flutter passent.

## Cas limites et erreurs

- **Code du livreur** :
  - commande pas à l'état « livreur en route » : refus (409) ;
  - pharmacie d'autrui : 404 (règle d'accès du projet) ;
  - livreur retiré de la mission entre-temps : refus, la commande repart en recherche de livreur.
- **Livreur sans position récente** : pas d'heure d'arrivée, l'app affiche « en route ».
- **Alerte sans quartier proche** (hors Lomé) : pas de quartier, l'app n'affiche que la distance.
- **Photo de devanture** : absente ou refusée, l'app garde la tuile du logo ; le lien expiré se
  relit.
- **Anciennes commandes** livrées avant ce changement : elles restent dans l'historique avec leur
  dû ; aucun versement ne leur est fait par l'app (l'équipe ivia les règle à part si besoin).
- **Anciens comptes de versement** : gardés en base, non affichés.
- **Sonnerie** : un jeton enregistré sans choix vaut « sonnerie active ».
- **PDF** : fichier trop lourd (5 Mo) refusé dès le choix, comme les photos.

## Hors périmètre

- Le versement réel au livreur de l'argent avancé (module de règlement des livreurs, inexistant
  aujourd'hui) : le montant est enregistré et visible, son règlement est fait par l'équipe ivia
  à part. À traiter dans une spec à venir.
- Les livraisons des boutiques (hors pharmacie) : inchangées.
- La partie « mobile » antérieure à la 031 (pharmacie validée qui voit le formulaire de création
  si la lecture échoue au lancement) : déjà notée dans `TASKS.md`, traitée à part.

## Questions ouvertes

Aucune.
