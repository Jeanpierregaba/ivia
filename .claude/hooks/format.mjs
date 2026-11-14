// PostToolUse : formate automatiquement chaque fichier modifié par l'agent.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { projectDir, readStdinJson, relativeToProject } from "./lib.mjs";

// Commande de formatage par extension ; le chemin du fichier est ajouté à la fin.
const PRETTIER = "pnpm --dir admin exec prettier --write --ignore-unknown";
const FORMAT_COMMANDS = {
  ".go": "gofmt -w",
  ".dart": "dart format",
  ".ts": PRETTIER,
  ".tsx": PRETTIER,
  ".css": PRETTIER,
  ".mjs": PRETTIER,
};

const input = readStdinJson();
const filePath = input.tool_input?.file_path;
if (!filePath) process.exit(0);

const FORMAT_COMMAND = FORMAT_COMMANDS[path.extname(filePath)];
if (!FORMAT_COMMAND) process.exit(0);

const absolute = path.resolve(projectDir, filePath);
const rel = relativeToProject(absolute);
// Uniquement les fichiers du projet, hors dépendances.
if (rel.startsWith("..") || /(^|\/)node_modules\//.test(rel) || !existsSync(absolute)) process.exit(0);

const result = spawnSync(`${FORMAT_COMMAND} ${JSON.stringify(absolute)}`, {
  cwd: projectDir,
  shell: true,
  encoding: "utf8",
});

if (result.status !== 0) {
  // Code 1 = erreur non bloquante : affichée à l'utilisateur, l'agent continue.
  process.stderr.write(`Formatage échoué pour ${rel} :\n${result.stderr || result.stdout || ""}`);
  process.exit(1);
}
