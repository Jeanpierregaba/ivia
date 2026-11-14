"use client";

import { useEffect, useState } from "react";

import { Field, fieldClass } from "@/components/ui";
import { formatXOF } from "@/lib/format";

type Product = { id: string; name: string; price_xof: number };

/**
 * Boutique du code et produits visés (spec 041) : toute la boutique, ou une sélection de ses
 * produits en vente (un seul ou plusieurs). Envoie `shop_id`, `scope` et `product_ids`.
 */
export function ProductScope({ shops }: { shops: { id: string; name: string }[] }) {
  const [shop, setShop] = useState(shops[0]?.id ?? "");
  const [some, setSome] = useState(false);
  const [products, setProducts] = useState<Product[] | null>(null);
  const [picked, setPicked] = useState<string[]>([]);
  const [query, setQuery] = useState("");

  useEffect(() => {
    if (!some || !shop) return;
    let live = true;
    fetch(`/coupons/products?shop=${shop}`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : { items: [] }))
      .then((b: { items: Product[] }) => {
        if (live) setProducts(b.items ?? []);
      })
      .catch(() => {
        if (live) setProducts([]);
      });
    return () => {
      live = false;
    };
  }, [some, shop]);

  const shown = (products ?? []).filter((p) => p.name.toLowerCase().includes(query.trim().toLowerCase()));

  return (
    <>
      <Field label="Boutique">
        <select
          name="shop_id"
          required
          className={fieldClass}
          value={shop}
          onChange={(e) => {
            setShop(e.target.value);
            setPicked([]);
            setProducts(null);
          }}
        >
          {shops.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </Field>
      <Field label="S'applique à">
        <select
          name="scope"
          className={fieldClass}
          value={some ? "products" : "shop"}
          onChange={(e) => setSome(e.target.value === "products")}
        >
          <option value="shop">Toute la boutique</option>
          <option value="products">Certains produits</option>
        </select>
      </Field>
      {some && (
        <div className="sm:col-span-2">
          <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
            <span className="text-[13px] font-semibold">
              Produits concernés {picked.length > 0 && `(${picked.length})`}
            </span>
            <input
              type="search"
              placeholder="Chercher un produit"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className={`${fieldClass} max-w-[240px]`}
            />
          </div>
          <div className="max-h-56 overflow-y-auto rounded-[14px] border border-border bg-white p-2">
            {products === null ? (
              <p className="p-2 text-text-muted">Chargement…</p>
            ) : shown.length === 0 ? (
              <p className="p-2 text-text-muted">Aucun produit en vente.</p>
            ) : (
              shown.map((p) => (
                <label
                  key={p.id}
                  className="flex cursor-pointer items-center gap-3 rounded-[10px] px-2 py-1.5 hover:bg-background"
                >
                  <input
                    type="checkbox"
                    name="product_ids"
                    value={p.id}
                    checked={picked.includes(p.id)}
                    onChange={(e) =>
                      setPicked((cur) => (e.target.checked ? [...cur, p.id] : cur.filter((x) => x !== p.id)))
                    }
                    className="size-4 accent-primary"
                  />
                  <span className="min-w-0 flex-1 truncate">{p.name}</span>
                  <span className="tabular-nums text-text-muted">{formatXOF(p.price_xof)}</span>
                </label>
              ))
            )}
          </div>
          <p className="mt-1 text-[12px] text-text-muted">
            La réduction ne porte que sur ces produits dans le panier.
          </p>
        </div>
      )}
    </>
  );
}
