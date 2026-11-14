import { ChevronLeft } from "lucide-react";
import Link from "next/link";

import { Card, PageHeader } from "@/components/ui";
import { PropertyForm } from "../property-form";

export const metadata = { title: "Nouvelle annonce" };

export default function NewPropertyPage() {
  return (
    <>
      <Link
        href="/properties"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Immobilier
      </Link>
      <PageHeader overline="Réseau" title="Nouvelle annonce" highlight="annonce" />
      <Card>
        <PropertyForm />
      </Card>
    </>
  );
}
