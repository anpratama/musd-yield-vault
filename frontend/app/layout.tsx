import type { Metadata } from "next";
import { Providers } from "./providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "MUSD Yield Vault — Mezo Buildathon",
  description:
    "ERC-4626 auto-yield vault for MUSD on Mezo. Deposit MUSD, earn yield from Mezo-native strategies.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
