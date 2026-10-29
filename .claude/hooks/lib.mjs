// Utilitaires partagés par les hooks. Aucune dépendance : seulement Node.
import { readFileSync } from "node:fs";
import path from "node:path";

export const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

export function readStdinJson() {
  try {
    const raw = readFileSync(0, "utf8");
    return raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export function readProjectFile(relativePath) {
  try {
    return readFileSync(path.join(projectDir, relativePath), "utf8");
  } catch {
    return null;
  }
}

export function stripHtmlComments(text) {
  return text.replace(/<!--[\s\S]*?-->/g, "");
}

// Chemin relatif au projet, avec des "/" quel que soit l'OS.
export function relativeToProject(filePath) {
  const absolute = path.resolve(projectDir, filePath);
  return path.relative(projectDir, absolute).split(path.sep).join("/");
}
