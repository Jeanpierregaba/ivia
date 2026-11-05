# Aperçu local (sans émulateur)

Toute la plateforme dans le navigateur, apps dans un cadre iPhone 17 Pro.

1. Lancer Docker Desktop.
2. Construire les apps (une fois, puis après chaque changement), depuis `mobile/apps/<app>` :
   `flutter build web --profile --no-web-resources-cdn --dart-define=API_BASE_URL=http://localhost:8090 --dart-define=IVIA_DEV_OTP=true --dart-define=IVIA_DEV_PAYMENT=true`
3. Construire l'API (`go build -o bin/api.exe ./cmd/api` dans `backend/`) et le back-office (`pnpm build` dans `admin/`).
4. `powershell -File tools\preview\demarrer.ps1` (arrêt : `-Stop`).

| App | Adresse |
| --- | --- |
| Acheteur | http://localhost:8090 |
| Marchand | http://localhost:8091 |
| Livreur | http://localhost:8092 |
| Back-office | http://localhost:3000 |

Local uniquement : codes de connexion remplis seuls, paiements validés par le faux prestataire,
pharmacies de démonstration (`manage seed-demo`) qui répondent aux alertes.
