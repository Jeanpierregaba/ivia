# mobile — apps Flutter ivia

Pub workspace ([ADR 0002](../docs/decisions/0002-trois-apps-flutter-workspace.md)) :

| Dossier | Paquet | Rôle |
|---|---|---|
| `apps/buyer` | `ivia_buyer` | App acheteur (« ivia ») |
| `apps/seller` | `ivia_seller` | App marchand (« ivia Marchand ») |
| `apps/driver` | `ivia_driver` | App livreur (« Ivia Driver », ex-« ivia Livreur ») |
| `packages/ui` | `ivia_ui` | Thème Material 3, tokens et police Parkinsans ([charte](../docs/DESIGN.md)) |
| `packages/api_client` | `ivia_api_client` | Accès à l'API, seul point de contact avec le backend |

Les commandes (installer, lancer, tester, construire) sont dans [`AGENTS.md`](../AGENTS.md#commandes).

Règles : les écrans utilisent `Theme.of(context)` et les tokens de `ivia_ui`, jamais de couleur,
taille de police ou rayon en dur ; tout appel réseau passe par `ivia_api_client`.
