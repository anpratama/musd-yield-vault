#!/usr/bin/env node
/**
 * Copies the Foundry deploy output (../deployments-31611.json) into
 * public/ so the frontend can load it as a fallback when the
 * NEXT_PUBLIC_* env vars are not set. Runs on `predev` / `prebuild`.
 * No-op when the file does not exist yet (vault not deployed).
 */
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "..", "deployments-31611.json");
const dest = join(root, "public", "deployments-31611.json");

if (existsSync(src)) {
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(src, dest);
  console.log(`[sync-deployments] copied ${src} -> ${dest}`);
} else {
  console.log("[sync-deployments] no deployments-31611.json yet — skipping");
}
