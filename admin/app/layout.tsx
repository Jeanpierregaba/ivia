import type { Metadata } from "next";
import { Parkinsans } from "next/font/google";

import { Splash } from "@/components/splash";

import "./globals.css";

const parkinsans = Parkinsans({ subsets: ["latin"], variable: "--font-parkinsans", display: "swap" });

export const metadata: Metadata = {
  title: { default: "ivia — back-office", template: "%s · ivia" },
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className={parkinsans.variable} suppressHydrationWarning>
      <body className="min-h-screen font-sans text-[15px] leading-[22px] antialiased">
        <Splash />
        {children}
      </body>
    </html>
  );
}
