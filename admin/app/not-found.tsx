import Link from "next/link";

export default function NotFound() {
  return (
    <main className="grid min-h-screen place-items-center px-4">
      <div className="text-center">
        <h1 className="text-[22px] font-bold">Page introuvable</h1>
        <p className="mt-2 text-text-secondary">Cette ressource n&apos;existe pas ou plus.</p>
        <Link href="/" className="mt-4 inline-block font-semibold text-secondary hover:underline">
          Retour au tableau de bord
        </Link>
      </div>
    </main>
  );
}
