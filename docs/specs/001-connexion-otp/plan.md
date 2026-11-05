# 001 — Plan technique (v2)

## Backend (fait)

- **Migration `00029_auth_phone_tokens.sql`** (additive) :
  - `otp_codes` : identifiant `phone`, colonne `sent_via`, usages `phone_login` et `phone_change` ;
  - `users.phone_verified_at` ;
  - tables `auth_recipient_locks`, `auth_pending_signups`, `auth_devices` ;
  - `sessions` : colonnes `refresh_hash`, `previous_refresh_hash`, `refreshed_at`,
    `access_expires_at`, `device_id`, `app` ;
  - tables `auth_totp` et `auth_recovery_codes`.
- **Module `auth`** :
  - `phone.go` : demande de code, vérification, inscription en attente, appareils, renouvellement,
    changement de numéro, sessions ;
  - `totp.go` : application d'authentification et codes de secours ;
  - `whatsapp_sender.go` : API Cloud de Meta, et `ChannelRouter` qui confie chaque canal à son
    expéditeur.
- **`sendCodeVia`** : essaie les canaux dans l'ordre (WhatsApp, puis SMS) et note celui qui a servi.
- **`Authenticate`** : répond `access_token_expired` quand le jeton d'accès d'une session à
  rafraîchissement a expiré.
- **Configuration** :
  - `PHONE_OTP_SENDER` : `none`, `log` (local) ou `whatsapp` ;
  - `SMS_SENDER` : `none` ou `log` ;
  - `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_ACCESS_TOKEN(_FILE)`, `WHATSAPP_TEMPLATE(_LANG)` ;
  - `PHONE_CODES_PER_HOUR`.
- **Alertes** (module notifications) :
  - `new_buyer` (admins) ;
  - `auth_otp_cap` (admins) ;
  - `new_device_login` (utilisateur, dans son app).

### Routes

| Route | Rôle |
| --- | --- |
| `POST /v1/auth/phone/code` | envoyer le code (public) |
| `POST /v1/auth/phone/verify` | `signed_in` + session, ou `signup_required` + `signup_token` |
| `POST /v1/auth/phone/signup` | créer le compte et ouvrir la session |
| `POST /v1/auth/refresh` | nouveau couple de jetons |
| `GET /v1/me/sessions`, `DELETE /v1/me/sessions/{id}` | appareils connectés |
| `POST /v1/me/phone/code`, `POST /v1/me/phone` | changer de numéro |
| `POST /v1/auth/mfa/totp/setup`, `confirm`, `recovery-codes`, `disable` | application d'authentification |
| `POST /v1/admin/users/{id}/mfa/reset` | réinitialiser l'application d'un autre admin |
| `GET /v1/auth/session` | renvoie aussi `mfa_method` et `recovery_codes_left` |
| `POST /v1/auth/mfa/verify` | accepte aussi un code de l'application ou un code de secours |

### Tests

- `internal/app/auth_phone_test.go` : inscription et connexion, verrou, renouvellement et
  réutilisation, changement de numéro, TOTP admin.
- `internal/auth/phone_test.go` : secours SMS, tous canaux en panne, plafond global, format du
  message WhatsApp.

## App acheteur (à faire)

**`api_client`**
- Appels `requestPhoneCode`, `verifyPhone`, `phoneSignup`, `refresh`, `listSessions`,
  `revokeSession`, `requestPhoneChange`, `confirmPhoneChange`.
- `SessionStore` garde le jeton d'accès, le jeton de rafraîchissement et l'identifiant
  d'installation (stockage sécurisé).
- L'intercepteur renouvelle le jeton une seule fois à la fois sur `access_token_expired`, puis
  rejoue la requête.

**`app_core`**
- `PhoneScreen`, `PhoneCodeScreen` et `ProfileScreen` v2 (sans téléphone), à la place des écrans
  e-mail.
- `LoginFlow` garde le numéro, le canal et le jeton d'inscription.
- Ces écrans servent aussi au marchand et au livreur.

**Acheteur** : Profil › Sécurité (appareils connectés, changer de numéro).

## Back-office (à faire)

- Écran du second facteur selon `mfa_method`.
- Page « Sécurité » : QR code généré dans le navigateur, codes de secours, sessions.
- Bouton « Réinitialiser la double vérification » sur la fiche d'un admin.
