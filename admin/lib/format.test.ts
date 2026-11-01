import { describe, expect, it } from "vitest";

import { formatDateTime, formatPhone, formatXOF, lomeDate, ORDER_STATUS, statusOf } from "./format";

describe("formatXOF", () => {
  it("sépare les milliers et n'affiche pas de décimales", () => {
    expect(formatXOF(12500).replace(/\s/g, " ")).toBe("12 500 FCFA");
    expect(formatXOF(0).replace(/\s/g, " ")).toBe("0 FCFA");
  });
});

describe("formatDateTime", () => {
  it("affiche l'heure de Lomé (UTC toute l'année)", () => {
    expect(formatDateTime("2026-11-01T14:05:00Z")).toContain("14:05");
  });
  it("affiche un tiret sans date", () => {
    expect(formatDateTime(null)).toBe("—");
  });
});

describe("lomeDate", () => {
  it("retourne la date du jour à Lomé", () => {
    expect(lomeDate(new Date("2026-11-01T23:30:00Z"))).toBe("2026-11-01");
  });
});

describe("formatPhone", () => {
  it("groupe un numéro togolais", () => {
    expect(formatPhone("+22890123456")).toBe("+228 90 12 34 56");
  });
  it("laisse un format inattendu tel quel", () => {
    expect(formatPhone("123")).toBe("123");
  });
});

describe("statuts", () => {
  it("couvre les 15 statuts de la machine à états", () => {
    expect(Object.keys(ORDER_STATUS)).toHaveLength(15);
  });
  it("affiche le code d'un statut inconnu plutôt que rien", () => {
    expect(statusOf(ORDER_STATUS, "nouveau").label).toBe("nouveau");
  });
});
