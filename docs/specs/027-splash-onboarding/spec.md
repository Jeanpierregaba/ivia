# 027 — Écran de lancement (splash) et présentation (onboarding)

## Objectif

Donner à chaque app (acheteur, marchand, livreur) une identité dès son ouverture, puis expliquer en
trois écrans, au premier lancement seulement, ce que l'app permet de faire. Le public visé n'utilise
souvent que WhatsApp et Mobile Money ([PRD](../../PRD.md)) : il faut le rassurer avant de lui
demander son e-mail.

## Comportement attendu

**Splash** (maquettes fournies par le porteur du projet le 2026-10-30) :

| App | Fond | Logo |
|---|---|---|
| Acheteur | Imperial Red `#ED1C2F` | Logotype blanc, centré |
| Marchand | Berkeley Blue `#0E2E54` | Logotype Berkeley Blue dans une tuile blanche à coins arrondis, centrée |
| Livreur | Cobalt Blue `#004DA8` | Logotype Cobalt Blue dans une tuile blanche à coins arrondis, centrée |

1. L'utilisateur ouvre l'app : le splash s'affiche immédiatement, avant même que Flutter démarre.
2. Il reste affiché le temps de l'initialisation (lecture de l'état local), sans délai artificiel.
3. Ensuite :
   - au premier lancement, la présentation s'ouvre ;
   - aux lancements suivants, l'écran de connexion s'ouvre directement (pour l'instant, un écran
     provisoire en attendant la fonctionnalité 001).

**Présentation** : trois pages qu'on fait défiler (balayage ou bouton « Suivant »). Chaque page
comporte une illustration, un titre court et une phrase. Un indicateur montre la page en cours, et un
bouton « Passer » en haut permet de sauter la présentation. Sur la dernière page, le bouton devient
« Commencer ». « Passer » comme « Commencer » mènent à l'écran de connexion, et la présentation n'est
plus jamais montrée sur cet appareil.

Contenu proposé (à valider) :

| App | Page 1 | Page 2 | Page 3 |
|---|---|---|---|
| Acheteur | **Les boutiques de Lomé dans votre poche** — Trouvez un produit près de chez vous, avec son prix et sa disponibilité. | **Payez par Flooz ou T-Money** — Votre paiement est confirmé avant que la boutique prépare votre commande. | **Retrait ou livraison, à vous de choisir** — Suivez votre commande étape par étape et remettez votre code à la réception. |
| Marchand | **Votre boutique en ligne** — Créez-la en quelques minutes ; ivia la vérifie avant de la publier. | **Des commandes déjà payées** — Acceptez-les en un geste, l'acheteur a payé par Mobile Money. | **Une remise sans litige** — Le code de l'acheteur confirme chaque remise ; vos relevés sont tenus pour vous. |
| Livreur | **Des missions près de vous** — Recevez des propositions selon votre position et votre véhicule. | **Guidé de la boutique au client** — Itinéraire, récupération, puis code du client pour terminer. | **Disponible quand vous le décidez** — Votre position n'est partagée que lorsque vous êtes en service. |

Les illustrations sont provisoires (pictogrammes) jusqu'à la livraison des illustrations du designer.

## Critères d'acceptation

- [ ] Étant donné une première installation, quand l'utilisateur ouvre l'app, alors le splash de son
      app s'affiche, puis la page 1 de la présentation.
- [ ] Étant donné la présentation ouverte, quand l'utilisateur appuie sur « Suivant » (ou balaie),
      alors la page suivante s'affiche et l'indicateur se met à jour.
- [ ] Étant donné la page 3, alors le bouton principal affiche « Commencer » ; un appui ouvre l'écran
      de connexion.
- [ ] Étant donné n'importe quelle page, quand l'utilisateur appuie sur « Passer », alors l'écran de
      connexion s'ouvre.
- [ ] Étant donné une présentation terminée ou passée, quand l'utilisateur relance l'app, alors
      il arrive sur l'écran de connexion sans revoir la présentation.
- [ ] Étant donné la page 2 ou 3, quand l'utilisateur fait « retour », alors la page précédente
      s'affiche ; sur la page 1, « retour » quitte l'app.
- [ ] Étant donné la police du téléphone agrandie à 200 % ou un écran de 320 dp de large, alors aucun
      texte n'est tronqué ni ne déborde, et aucun mot de titre n'est coupé (les titres sont plafonnés
      à 150 %, le texte courant suit les 200 %).
- [ ] Le lecteur d'écran annonce « ivia » sur le logo, le titre et le texte de chaque page, et
      « Page n sur 3 » à chaque changement de page.
- [ ] Les couleurs et le texte respectent les contrastes de `docs/DESIGN.md` (bouton principal
      Imperial Red dans les trois apps).

## Cas limites et erreurs

- **Lecture de l'état local impossible** (stockage corrompu) : on montre la présentation. C'est
  sans risque et l'app ne bloque pas.
- **Écriture impossible** : on navigue quand même vers la connexion. La présentation reviendra au
  prochain lancement, ce qui est acceptable.
- **App fermée pendant la présentation** : elle reprend à la page 1 au lancement suivant.
- **Données de l'app effacées ou réinstallation** : la présentation revient (l'état est propre à
  l'appareil, il n'est pas lié au compte).
- **Hors ligne** : splash et présentation n'ont besoin d'aucun réseau.
- **Rotation** : les apps restent en portrait (voir Hors périmètre) ; aucun état ne doit être perdu
  si l'écran est reconstruit.

## Hors périmètre

- L'écran de connexion lui-même (fonctionnalité 001) : ici, un écran provisoire seulement.
- Le saut du splash vers l'accueil quand une session existe : il viendra avec la fonctionnalité 001.
- Les demandes de permissions (localisation du livreur, notifications) : elles viendront avec leurs
  fonctionnalités (012, 019), au moment où elles servent.
- Les illustrations définitives, l'icône de lancement des apps et les identifiants
  `com.example.*` : démarches suivies dans `TASKS.md`.
- Le mode paysage et le mode sombre.

## Questions ouvertes

- Contenu des 3 pages × 3 apps ci-dessus : à valider ou corriger.
