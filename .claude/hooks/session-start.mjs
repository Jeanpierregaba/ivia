// SessionStart : redonne à l'agent le contexte de reprise (statut du cadrage, tâches en cours,
// dernière entrée du journal). Ce qui est écrit sur stdout est ajouté au contexte de la session.
import { readProjectFile, stripHtmlComments } from "./lib.mjs";

const MAX_CHARS = 3000;

function section(markdown, title) {
  const lines = stripHtmlComments(markdown).split("\n");
  const start = lines.findIndex((l) => l.trim().toLowerCase() === `## ${title}`.toLowerCase());
  if (start === -1) return "";
  const end = lines.findIndex((l, i) => i > start && /^##\s/.test(l));
  return lines
    .slice(start + 1, end === -1 ? undefined : end)
    .join("\n")
    .trim();
}

function lastLogEntry(markdown) {
  const text = stripHtmlComments(markdown);
  const match = text.match(/^###\s[\s\S]*?(?=^###\s|(?![\s\S]))/m);
  return match ? match[0].trim() : "";
}

const out = [];

const agents = readProjectFile("AGENTS.md");
if (agents) {
  const status = section(agents, "Statut du cadrage").split("\n")[0].replace(/\*/g, "").trim();
  if (status) out.push(`Statut du cadrage : ${status}`);
  if (/NON FAIT/.test(status)) {
    out.push("Le cadrage n'est pas fait : avant de coder une fonctionnalité, propose /cadrage.");
  }
}

const tasks = readProjectFile("TASKS.md");
if (tasks) {
  const current = section(tasks, "En cours");
  out.push(`Tâches en cours (TASKS.md) :\n${current || "(aucune)"}`);
}

const log = readProjectFile("docs/SESSION-LOG.md");
if (log) {
  const entry = lastLogEntry(log);
  if (entry) out.push(`Dernière session (docs/SESSION-LOG.md) :\n${entry}`);
}

if (out.length) {
  const text = `Contexte de reprise du projet\n\n${out.join("\n\n")}`;
  process.stdout.write(text.length > MAX_CHARS ? `${text.slice(0, MAX_CHARS)}\n…(tronqué)` : text);
}
