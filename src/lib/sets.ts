import fs from "node:fs";
import path from "node:path";

type CardImage = { thumb: string; full: string; file?: string };
type Manifest = Record<string, Record<string, CardImage[]>>;

export function loadSetsManifest(): { generatedAt?: string; manifest: Manifest } {
  // During `astro build`, process.cwd() is repo root on Cloudflare too.
  const filePath = path.join(process.cwd(), "public", "sets.json");

  if (!fs.existsSync(filePath)) {
    throw new Error(
      `Missing public/sets.json. Make sure your prebuild script generates it. Looked for: ${filePath}`
    );
  }

  const raw = fs.readFileSync(filePath, "utf-8");
  const data = JSON.parse(raw);

  if (!data || typeof data !== "object" || !data.manifest) {
    throw new Error("public/sets.json has unexpected format (missing manifest).");
  }

  return data as { generatedAt?: string; manifest: Manifest };
}