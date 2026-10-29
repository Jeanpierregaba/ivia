---
name: audit-securite
description: Audit de sécurité de l'application à partir de docs/SECURITY.md - vérifie le code réel, pas seulement la doc. À utiliser avant une mise en production, après une fonctionnalité touchant l'auth, les paiements ou les données personnelles, ou sur demande.
argument-hint: "[périmètre, optionnel : dossier, fonctionnalité ou 'tout']"
---

# Audit de sécurité

Périmètre : $ARGUMENTS (par défaut : tout le projet).

1. Lis `docs/SECURITY.md`, `docs/RULES.md` et la partie auth / données de `docs/ARCHITECTURE.md`.
2. Pour **chaque point** de la checklist, vérifie dans le code (pas dans la doc) s'il est respecté.
   Cite le fichier et la ligne comme preuve. Statut : OK / À corriger / Non applicable / Non vérifiable.
3. Cherche en plus :
   - secrets en dur (clés, tokens, mots de passe, URL avec identifiants), y compris dans l'historique git
   - variables d'environnement secrètes exposées au client
   - routes / actions serveur sans contrôle d'accès, ou qui ne vérifient pas la propriété de la ressource
   - entrées non validées, SQL concaténé, HTML non échappé
   - dépendances vulnérables (lance l'outil d'audit de la stack)
   - si l'app utilise un LLM : contenu externe injecté dans les prompts sans séparation, outils trop permissifs
4. Rends un rapport classé par gravité (critique / haute / moyenne / basse), avec pour chaque
   problème : où, risque concret, correction proposée.
5. Ne corrige qu'après validation. Mets à jour les cases de `docs/SECURITY.md` en fonction du résultat.
