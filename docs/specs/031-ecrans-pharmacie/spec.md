# 031 — Écrans de l'app pharmacie d'après les maquettes

## Objectif

L'app pharmacie (ivia Pharmacie) fonctionne déjà : dossier, alertes, réponses, réservations, solde,
push. Gedeon a fait le dossier en 5 étapes et le push (sonnerie, plein écran). Elle n'a pas encore
de design. Cette spec habille **toute l'app** fidèlement aux 24 maquettes du designer, déposées le
2026-11-06 dans [`maquettes/`](maquettes/), de F00 à F23, au format 360 × 780 dp en @2x. Le
comportement du serveur ne change pas : l'app affiche ce que l'API fournit, sans rien inventer
([PRD](../../PRD.md), alertes médicament).

Arbitrages du porteur du projet (2026-11-06) :
- **Connexion** : seulement par numéro (ADR 0012). L'onglet « E-mail » de F04 est retiré. Les deux
  canaux de l'écran commun restent : WhatsApp, puis SMS.
- **Dossier** : on garde les 5 étapes de Gedeon (fiche, carte, pièces, planning, versement),
  habillées au style de F06 à F08. L'API exige l'e-mail et le compte de versement, absents des
  maquettes.
- **Alerte entrante et sonnerie** : on s'appuie sur le push de Gedeon (`push.dart`).
- **Données absentes de l'API** (voir « Hors périmètre ») : l'écran fait sans, et les manques sont
  notés pour Gedeon.

## Comportement attendu

**Charte commune**
- Fond `#F3F4F6`, cartes blanches à grands rayons, texte `#0A1A30`, texte secondaire `#5A6A80`.
- Vert `#0B7A55` et vert foncé `#075C40` ; rouge des urgences sur fond rose `#FDE8EA`.
- Boutons en pilule pleine largeur en bas d'écran. Bouton retour rond et blanc, titre centré,
  pastille à droite (étape « 1 sur 5 », compte à rebours).
- Police Parkinsans.

**Lancement** (F00 à F03)
1. **Splash (F00)** : plein écran vert, tuile blanche au logo vert, « Pharmacie » et « Répondez aux
   urgences de votre quartier. », trois points en bas.
2. **Localisation** (030, inchangée).
3. **Présentation** : nouvelle pour la pharmacie, montrée une fois. Trois pages :
   - « Les urgences de votre quartier, **en direct.** » ;
   - « Répondez **en moins d'une minute.** » ;
   - « Le client confirme, **vous préparez.** ».

   Chaque page a ses illustrations de la maquette, des points de progression, « Passer » (pages 1
   et 2), un retour (pages 2 et 3), puis « Suivant » ou « Commencer ».
4. **Connexion (F04)** : tuile du logo et pastille verte « Pharmacie », « Espace pharmacie », texte
   « Connectez-vous avec votre numéro. Nous vous envoyons un code. », champ « +228 ». Ensuite
   « Recevoir le code sur WhatsApp », « Recevoir par SMS », et en bas « En continuant, vous acceptez
   les **Conditions partenaires** et la **Politique de confidentialité**. ».
5. **Code (F05)** : retour rond. Le titre suit le canal (« Vérifiez vos SMS » ou « Vérifiez
   WhatsApp ») et le texte rappelle le numéro, avec « Modifier ». Puis six cases, « Renvoyer le code
   dans 0:42 », et « Valider » en bas, gris tant que le code est incomplet.

**Dossier** (F06 à F08, 5 étapes, en-tête « Votre pharmacie », pastille « n sur 5 »)
1. **Fiche** :
   - photo de la devanture (zone hachurée avec « Ajouter »), nom, numéro d'autorisation,
     téléphone, e-mail, adresse, quartier et horaires ;
   - aperçu « Position sur la carte », qui ouvre l'étape 2 ;
   - la photo choisie est envoyée dès que la pharmacie est créée.
2. **Carte** : déplacer la carte sous le repère vert, « Utiliser ma position », « Confirmer cet
   emplacement ». La pharmacie est enregistrée en brouillon.
3. **Documents (F07)** : « Vérification de la pharmacie », « Ces documents sont vus uniquement par
   l'équipe ivia. ».
   - Une ligne par pièce : autorisation d'exercice, pièce d'identité du responsable et inscription à
     l'Ordre (facultative). Chaque ligne affiche « Ajouter » (case pointillée) ou « Ajouté » (case
     verte cochée).
   - La case « Je certifie être titulaire ou gérant de cette pharmacie. » est obligatoire pour
     continuer.
4. **Planning de garde** : l'écran Planning (F20), dans le parcours. On peut passer cette étape.
5. **Compte de versement** : opérateur, numéro Mobile Money et titulaire. Puis « Envoyer pour
   validation », gris tant qu'une pièce obligatoire ou le compte manque.

**Retour sur le dossier**
- Un brouillon reprend à la première étape incomplète. Le retour ramène à l'étape précédente.
- « Compléments demandés » ou « refusé » : le motif s'affiche en haut de l'étape 1, et toutes les
  étapes sont modifiables.

**Après l'envoi : en cours de validation (F08)**
- Anneau de progression, « Votre pharmacie est en cours de validation », « L'équipe ivia vérifie
  votre autorisation d'exercice. Vous recevrez une notification et un e-mail. ».
- Une frise à 4 étapes : Compte créé ✓, Dossier envoyé ✓ (nom de la pharmacie), Vérification par
  ivia (En cours), Réception des alertes (Dès la validation).
- « Préparer mon planning de garde » ouvre le planning. Tirer vers le bas actualise le statut.
- Pharmacie suspendue : même écran avec le texte de suspension.

**Barre du bas** : barre flottante blanche à 4 onglets (Accueil, Alertes, Commandes, Profil). L'onglet
actif est une pilule verte avec son libellé. Les alertes nouvelles s'affichent en pastille rouge sur
la cloche.

**Accueil (F09)**
- En-tête vert : photo, nom et ligne de garde (« De garde · 20:00 → 08:00 » pendant une garde,
  sinon « En service » ou « Hors service »).
- Carte « En service · Vous recevez les alertes » avec interrupteur (ouverte / fermée).
- Trois chiffres du jour : Alertes, Répondues, Confirmées.
- « Alertes à traiter » avec « Tout voir » : cartes à bord rouge des alertes ouvertes, avec
  « Nouvelle » si l'alerte n'a pas été vue et un compte à rebours. Chaque carte affiche
  « n produits · ordonnance · client à 650 m », puis « Voir » et « Répondre ».
- Une carte « n commande(s) à préparer », avec l'heure limite de mise de côté, ouvre les commandes.

**Alerte entrante (F10)**
- Plein écran vert foncé : cloche dans des cercles, « ALERTE MÉDICAMENT », « n produits demandés »,
  « Client à 650 m · ordonnance jointe ».
- Pastille « 19:58 pour répondre », puis « Voir l'alerte » et « Ignorer ».
- Elle s'ouvre quand on touche la notification du push, ou quand une alerte arrive app ouverte.
- « Ignorer » refuse l'alerte, comme dans le détail : elle passe « Ignorée » dans l'historique.

**Détail de l'alerte (F11)**
- Compte à rebours en haut. Carte « Ordonnance · n page(s) » avec la miniature et « Touchez pour
  agrandir ».
- « Produits demandés » avec forme et quantité, et « Générique accepté » si le client l'a coché.
- « Précision du client », puis « Client anonyme jusqu'à la confirmation · à 650 m ».
- « Ignorer » et « Répondre ».

**Ordonnance (F12)** : fond bleu nuit, fermer, « Page n sur N », pivoter, zoom au doigt et par
boutons (− 200 % +). Le bas d'écran dit « photo supprimée 24 h après l'alerte ». Sur Android, il
dit aussi « Capture d'écran désactivée », et la capture est bien bloquée sur cet écran.

**Réponse (F13)**
- Une carte par produit : « Demandé : n », interrupteur « Disponible », prix unitaire (F) et
  quantité.
- « Générique : … » modifiable si le client accepte un générique. Case « Délivré sur ordonnance
  uniquement ».
- Carte « Total indicatif » et « n / N disponibles ». Pour une ordonnance en photo seule, on peut
  ajouter des produits.
- « Envoyer la réponse » mène à « Réponse envoyée » (F14) : produits disponibles, total et
  « Retour aux alertes ».

**Commande en retrait (F15, F16)**
- En-tête vert « Commande #M-208 », « Client confirmé », « Mettez les produits de côté jusqu'à
  00:25 ».
- Mode de remise « Retrait au comptoir ». Produits avec prix et mention « sur ordonnance », et
  « À encaisser sur place ».
- « Produits mis de côté » marque la commande préparée et ouvre la remise (F16) :
  - code du client en 4 cases ;
  - « J'ai vu l'original de l'ordonnance » (si un produit est sur ordonnance) et « Le client a payé
    7 450 F sur place » ;
  - rappel jaune des produits sur ordonnance ;
  - « Valider la remise », grisé tant que le code ou une case manque.
- Après la remise, écran de succès « Commande remise au client », dans le style de F19.

**Commande en livraison (F17, F19)**
- Carte « Payée dans l'app · n F versés sur votre relevé » et pastille « Livraison ».
- Produits, puis 3 étapes : Préparer la commande, Livreur en route (prénom du livreur), Remise au
  livreur.
- « Marquer prête » marque la commande préparée. Quand le livreur a récupéré la commande, l'écran
  « Commande remise au livreur » (F19) affiche « À vous verser ».

**Annulation (F18)** : « Signaler une rupture » ouvre une feuille « Annuler cette commande ? »
(« Le client est prévenu et remboursé. »).
- Motifs : Rupture de stock imprévue, Produit périmé ou endommagé, Erreur sur le prix, Autre motif.
  « Autre motif » ouvre un champ de texte.
- Boutons « Confirmer l'annulation » (rouge foncé) et « Garder la commande ».

**Planning (F20)**
- Bande des 7 jours de la semaine, avec un point sous les jours de garde, et « + » pour ajouter une
  garde.
- Le jour choisi liste :
  - le service de jour, d'après les heures de nuit de la pharmacie (« En service ») ;
  - ses gardes (« De garde »).
- Carte « Importer une liste » (import de Gedeon). Carte bleue : « En journée, les alertes vont à
  toutes les pharmacies en service. La nuit, uniquement aux pharmacies de garde. ».
- Réglage des heures de nuit.

**Alertes (F21)** : titre « Alertes », trois onglets.
- « En cours · n » : alertes ouvertes.
- « Commandes » : réservations en cours.
- « Historique » : lignes groupées par jour, avec une pastille d'état : Remise, Mise de côté,
  Répondue, Expirée, Ignorée.

**Commandes** (onglet du bas) : les réservations en cours, puis terminées, dans le même style de
lignes.

**Relevé (F22)**
- Carte verte « À recevoir » avec le solde, et « 0 % de commission » si les commandes n'en ont pas.
- « Seules les commandes livrées payées dans l'app apparaissent ici. Les retraits sont payés au
  comptoir. ».
- Commandes livrées (date, montant dû). Carte « Compte de versement » (opérateur et numéro
  masqué), qui ouvre le compte.

**Profil (F23)**
- Photo, nom et « Validée ».
- Lignes :
  - Informations (fiche ; ouverte 24 h/24 et garde en cours restent réglables ici) ;
  - Planning de garde (prochaine garde) ;
  - Documents (pièces envoyées) ;
  - Relevé des versements (solde à recevoir).
- Interrupteur « Sonnerie des alertes · Forte · répétée », pour ce téléphone.
- « Aide et contact ivia », « Se déconnecter ».

## Critères d'acceptation

- [ ] Étant donné un premier lancement, après le splash vert (F00) et la localisation, la
      présentation en 3 pages s'affiche une fois. « Passer » ou « Commencer » ouvre la connexion,
      et elle ne revient plus.
- [ ] La connexion (F04) n'a pas d'onglet e-mail. Elle affiche « Espace pharmacie », la pastille
      verte, WhatsApp puis SMS, et les « Conditions partenaires ». Les autres apps ne changent pas.
- [ ] Étant donné un code demandé par SMS, l'écran du code titre « Vérifiez vos SMS ». Par WhatsApp,
      il titre « Vérifiez WhatsApp ». « Valider » reste gris tant que le code n'a pas 6 chiffres.
- [ ] Étant donné un compte sans pharmacie, le dossier déroule 5 étapes numérotées « n sur 5 ». La
      devanture choisie à l'étape 1 est envoyée après la création. L'étape 3 exige la case
      « Je certifie… ». « Envoyer pour validation » reste gris tant qu'une pièce obligatoire ou le
      compte de versement manque.
- [ ] Étant donné un brouillon existant, l'app rouvre le dossier à la première étape incomplète.
- [ ] Étant donné des compléments demandés, le motif s'affiche et le dossier se modifie.
- [ ] Étant donné un dossier envoyé, l'écran F08 montre la frise. « Préparer mon planning de garde »
      ouvre le planning.
- [ ] Étant donné une pharmacie validée, l'Accueil (F09) affiche le nom, l'interrupteur « En
      service » (qui change le statut ouvert), les 3 chiffres du jour, les alertes ouvertes et la
      carte des commandes à préparer.
- [ ] La barre du bas montre la pilule verte sur l'onglet actif et la pastille du nombre d'alertes
      non vues.
- [ ] Étant donné un push d'alerte touché ou une alerte reçue app ouverte, l'écran F10 s'affiche.
      « Voir l'alerte » ouvre le détail (F11), et « Ignorer » refuse l'alerte.
- [ ] Le détail (F11) affiche les produits, « Générique accepté », la précision du client et la
      miniature. La miniature ouvre l'ordonnance en grand (F12), avec zoom et rotation.
- [ ] Étant donné l'ordonnance en grand sur Android, la capture d'écran est bloquée, puis permise de
      nouveau en quittant l'écran.
- [ ] La réponse (F13) calcule le total indicatif des produits disponibles et le compte
      « n / N disponibles ». Elle envoie prix, quantités, générique et mention « sur ordonnance ».
      Elle mène ensuite à « Réponse envoyée » (F14).
- [ ] Étant donné une commande en retrait confirmée, « Produits mis de côté » la marque préparée.
      La remise (F16) exige les 4 chiffres et les cases, puis affiche le succès. Un code faux affiche
      l'erreur sans quitter l'écran.
- [ ] Étant donné une commande en livraison, l'écran F17 montre l'étape en cours. « Marquer prête »
      la marque préparée, et une commande récupérée par le livreur affiche F19.
- [ ] « Signaler une rupture » ouvre la feuille F18. L'annulation envoie le motif choisi, ou le texte
      saisi pour « Autre motif ». « Garder la commande » ferme sans rien faire.
- [ ] Le planning (F20) affiche la semaine et les gardes du jour choisi, ajoute une garde (« + ») et
      règle les heures de nuit.
- [ ] L'onglet Alertes (F21) affiche « En cours · n », « Commandes » et « Historique » (groupé par
      jour, pastilles d'état).
- [ ] Le relevé (F22) affiche le solde, les commandes livrées et le compte de versement.
- [ ] Le profil (F23) ouvre Informations, Planning, Documents et Relevé. « Sonnerie des alertes »
      coupé ⇒ le push d'alerte ne sonne plus sur ce téléphone, mais la notification reste. « Se
      déconnecter » retire d'abord l'appareil du push.
- [ ] Chaque écran tient sans débordement en police à 200 % sur un écran de 320 dp, et les éléments
      interactifs ont un libellé pour le lecteur d'écran.

## Cas limites et erreurs

- **Réseau coupé** :
  - une liste affiche un message et « Tirer pour réessayer » ;
  - une action garde l'écran et affiche le message de l'API ;
  - les boutons ne partent pas deux fois.
- **Listes vides** : alertes, commandes, historique et relevé ont chacun un état vide.
- **Alerte expirée ou prise ailleurs** : ouverte depuis F10 ou depuis une notification, elle
  affiche « Alerte terminée » au lieu de la réponse. Une réponse envoyée trop tard affiche l'erreur
  de l'API.
- **Compte à rebours à zéro** : la pastille passe à « Terminée » et « Répondre » se désactive.
- **Ordonnance** :
  - sans photo : pas de carte Ordonnance ;
  - photo expirée (lien de 10 minutes) : on relit le détail ;
  - photo seule sans produit : la réponse part d'une ligne vide à remplir.
- **Commande** :
  - annulée ou expirée pendant qu'on la regarde : l'écran se met à jour et les actions
    disparaissent ;
  - pas encore de livreur : « Recherche d'un livreur ».
- **Dossier** :
  - photo de devanture refusée à l'envoi : l'étape 3 la redemande ;
  - erreur de champ à la création : retour à l'étape 1, champ en erreur.
- **Sans Firebase** (push non configuré) : l'app relit ses alertes. F10 s'affiche quand une nouvelle
  alerte apparaît à la relecture, app ouverte.

## Hors périmètre

- Changements du serveur. Manques à noter pour Gedeon :
  - numéro court d'alerte (« #A-3107 ») : l'app affiche à la place l'heure de réception ;
  - code du livreur saisi par la pharmacie à la remise (F17) : l'app indique que le livreur confirme
    dans son app ;
  - heure d'arrivée et heure de récupération du livreur ;
  - période du relevé et date de versement (« 1er au 15 nov », « le 16 nov ») ;
  - origine « planning officiel importé » ;
  - quartier du client (« Tokoin ») ;
  - montant du forfait remboursé (« 100 F ») ;
  - adresse de la photo de devanture (photo de profil).

  En attendant, la photo de profil est la tuile du logo.
- Envoi de PDF pour les pièces : photo seulement, comme aujourd'hui. « PDF ou photo » devient
  « Photo lisible ».
- Blocage de capture sur iOS : impossible à garantir, la mention n'y est pas affichée.
- Mise en service de Firebase (Gedeon, `docs/mise-en-service-push-pharmacie.md`).
- Mode sombre et tablette.

## Questions ouvertes

Aucune.
