# 029 — Module pharmacie (alerte médicament)

Diagrammes de flux (BPMN 2.0, à ouvrir dans Camunda Modeler) ; aperçus en PNG à côté.

| Fichier | Contenu |
| --- | --- |
| `alerte-medicament.bpmn` | Alerte du client → réponses des pharmacies → déblocage 100 F → retrait ou livraison ivia |
| `inscription-pharmacie.bpmn` | Inscription de la pharmacie, dépôt des pièces, validation par l'admin |

## Règles retenues

- **Alerte** : trois façons de chercher — photo de l'ordonnance, photo de la boîte, nom saisi.
- **Diffusion** : pharmacies validées par l'admin, ouvertes ou de garde, dans un rayon de 5 km (élargi si personne ne répond).
- **Réponses** : le système attend 3 à 4 réponses (10 min au plus) et les classe par distance.
- **Déblocage** : les identités restent grisées (nom, adresse, téléphone) jusqu'au paiement forfaitaire de 100 F via l'agrégateur.
- **Sur ordonnance** (alerte par ordonnance, ou médicament signalé « sur ordonnance » par la pharmacie) : pas de livreur ivia, retrait en pharmacie obligatoire.
- **Sinon**, le client choisit :
  - retrait en pharmacie, avec un code de retrait et le paiement sur place ;
  - livraison ivia, avec le paiement du médicament et de la livraison dans l'app, puis le reversement à la pharmacie moins la commission ivia.
- **Pharmacie** : inscription dans une app dédiée, puis validation par l'admin sur pièces avant de recevoir des alertes.

## Questions à trancher avant le backend

1. Déblocage : remboursé si la pharmacie choisie n'a finalement plus le produit ? Payé si une seule pharmacie répond ?
2. Les 100 F débloquent-ils toutes les pharmacies de la liste ou une seule ?
3. Commission ivia sur les ventes livrées : quel taux (comme les boutiques ?) ; frais de livraison : même barème que les commandes ?
4. Retrait en pharmacie : la réservation expire au bout de combien de temps ?
5. Pièces exigées pour une pharmacie (autorisation d'ouverture, inscription à l'Ordre des pharmaciens du Togo, pièce du titulaire) : liste à confirmer.
6. Données de santé : durée de conservation des photos d'ordonnance (proposé : supprimées 30 jours après l'alerte).
