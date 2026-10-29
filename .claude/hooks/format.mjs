// PostToolUse : formate automatiquement chaque fichier modifié par l'agent.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { projectDir, readStdinJson, relativeToProject } from "./lib.mjs";

// À RENSEIGNER pendant /cadrage, une fois la stack choisie. Le chemin du fichier est ajouté à la fin.
// Exemples :
//   "npx prettier --write --ignore-unknown"   (JS/TS, CSS, Markdown…)
//   "npx @biomejs/biome format --write"        (JS/TS)
//   "ruff format"                              (Python)
//   "gofmt -w"                                 (Go)
// Laisser vide désactive le formatage.
const FORMAT_COMMAND = "";

if (!FORMAT_COMMAND) process.exit(0);

const input = readStdinJson();
const filePath = input.tool_input?.file_path;
if (!filePath) process.exit(0);

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
