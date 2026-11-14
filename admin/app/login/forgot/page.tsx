import type { Metadata } from "next";

import { AuthShell } from "../auth-shell";
import { ForgotForm } from "./forgot-form";

export const metadata: Metadata = { title: "Mot de passe oublié" };

export default function ForgotPage() {
  return (
    <AuthShell>
      <ForgotForm />
    </AuthShell>
  );
}
