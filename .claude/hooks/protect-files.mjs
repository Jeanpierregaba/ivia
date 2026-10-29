// PreToolUse : bloque l'accès aux fichiers sensibles et les commandes git destructrices.
// Sortie code 2 = action refusée ; le message sur stderr est renvoyé à l'agent.
import path from "node:path";
import { readStdinJson, relativeToProject } from "./lib.mjs";

// Fichiers dont le contenu ne doit jamais être lu ni modifié par l'agent.
const SECRET_FILE = /(^|\/)\.env(\.(?!example$)[^/]+)?$|\.(pem|key|p12|pfx)$/i;
// Fichiers que l'agent peut lire mais ne doit modifier qu'avec les outils dédiés.
const GENERATED_FILE =
  /(^|\/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|poetry\.lock|uv\.lock|Cargo\.lock)$/;
const GIT_DIR = /(^|\/)\.git\//;

// Commandes shell qui mentionnent un fichier .env réel (pas .env.example).
const BASH_SECRET = /(^|[\s'"=<>|;&(/])\.env(\.(?!example\b)[\w.-]+)?(?![\w.-])/;
const BASH_FORCE_PUSH = /\bgit\s+push\b[^;&|]*\s(--force(?!-with-lease)|-f)(\s|$)/;
const BASH_RESET_HARD = /\bgit\s+reset\b[^;&|]*\s--hard\b/;

function deny(message) {
  process.stderr.write(`${message}\n`);
  process.exit(2);
}

const input = readStdinJson();
const tool = input.tool_name;
const toolInput = input.tool_input || {};

if (tool === "Bash") {
  const command = String(toolInput.command || "");
  if (BASH_SECRET.test(command)) {
    deny(
      "Bloqué par .claude/hooks/protect-files.mjs : la commande touche un fichier .env réel. " +
        "Les secrets ne sont pas accessibles à l'agent ; demande à l'utilisateur de faire cette action lui-même " +
        "(ou utilise .env.example pour documenter une variable)."
    );
  }
  if (BASH_FORCE_PUSH.test(command) || BASH_RESET_HARD.test(command)) {
    deny(
      "Bloqué par .claude/hooks/protect-files.mjs : commande git destructrice (push --force / reset --hard). " +
        "Voir docs/RULES.md. Si c'est vraiment nécessaire, l'utilisateur doit la lancer lui-même."
    );
  }
  process.exit(0);
}

const filePath = toolInput.file_path || toolInput.notebook_path;
if (!filePath) process.exit(0);

const rel = relativeToProject(filePath);
const name = path.posix.basename(rel);

if (SECRET_FILE.test(rel)) {
  deny(
    `Bloqué par .claude/hooks/protect-files.mjs : ${name} peut contenir des secrets. ` +
      "Documente les variables dans .env.example et demande à l'utilisateur de remplir le vrai fichier."
  );
}

if (tool !== "Read" && GIT_DIR.test(`${rel}/`)) {
  deny("Bloqué par .claude/hooks/protect-files.mjs : ne modifie pas le dossier .git directement, utilise les commandes git.");
}

if (tool !== "Read" && GENERATED_FILE.test(rel)) {
  deny(
    `Bloqué par .claude/hooks/protect-files.mjs : ${name} est généré. ` +
      "Modifie-le via le gestionnaire de paquets (install / add / remove), pas à la main."
  );
}

process.exit(0);
