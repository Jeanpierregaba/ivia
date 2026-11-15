import { describe, expect, it } from "vitest";

import { orderCode, orderCodeOfReference } from "./order-code";

describe("orderCode", () => {
  it("mêmes valeurs que l'API et les apps", () => {
    expect(orderCode(1)).toBe("HSWK-20E0");
    expect(orderCode(111)).toBe("NTNJ-CKVW");
    expect(orderCode(1042)).toBe("W8MB-QRCH");
    expect(orderCode(1043)).toBe("F4D6-PHF8");
    expect(orderCode(999999)).toBe("DC1D-KHHF");
    expect(orderCodeOfReference("IV-000111")).toBe("NTNJ-CKVW");
  });
});
