// scripts/build-good-cards.mjs
import fs from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const CARDS_DIR = path.join(ROOT, "public", "cards");
const OUT_FILE = path.join(ROOT, "public", "good-cards.json");

const exts = new Set([".webp", ".jpg", ".jpeg", ".png"]);

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

function relPublic(p) {
  // convert absolute path to site path like /cards/...
  const rel = path.relative(path.join(ROOT, "public"), p).split(path.sep).join("/");
  return "/" + rel;
}

function scoreFromFilename(name) {
  const n = name.toLowerCase();

  let score = 0;

  // "Good" signals (tweak these as you like)
  if (n.includes("1of1")) score += 50;
  if (n.includes("numbered-") || n.match(/\b\d+of\d+\b/)) score += 25;
  if (n.includes("auto") || n.includes("autograph")) score += 35;
  if (n.includes("relic") || n.includes("patch") || n.includes("jersey") || n.includes("bat")) score += 30;
  if (n.includes("rc") || n.includes("rookie")) score += 10;
  if (n.includes("gold")) score += 10;
  if (n.includes("orange")) score += 8;
  if (n.includes("red")) score += 8;
  if (n.includes("blue")) score += 6;
  if (n.includes("purple")) score += 6;
  if (n.includes("black")) score += 6;
  if (n.includes("refractor") || n.includes("prizm") || n.includes("chrome")) score += 8;
  if (n.includes("ssp") || n.includes("sp")) score += 15;

  // down-weight obvious base
  if (n.includes("__base")) score -= 5;

  return Math.max(score, 0);
}

function parseCardContext(filePath) {
  // expects: public/cards/<sport>/<set>/thumbs/<file>
  const parts = filePath.split(path.sep);
  const cardsIdx = parts.lastIndexOf("cards");
  if (cardsIdx === -1) return null;

  const sport = parts[cardsIdx + 1];
  const setSlug = parts[cardsIdx + 2];

  if (!sport || !setSlug) return null;

  // homepage + set browsing usually looks like /<sport>/<set>/
  const href = `/${sport}/${setSlug}/`;
  return { sport, setSlug, href };
}

function weightedPick(items) {
  // weight by score + 1
  const weights = items.map(i => (i.score ?? 0) + 1);
  const total = weights.reduce((a, b) => a + b, 0);
  let r = Math.random() * total;
  for (let i = 0; i < items.length; i++) {
    r -= weights[i];
    if (r <= 0) return items[i];
  }
  return items[items.length - 1];
}

function main() {
  if (!fs.existsSync(CARDS_DIR)) {
    console.error("Missing cards dir:", CARDS_DIR);
    process.exit(1);
  }

  // Use thumbs as the primary “preview” source
  const allFiles = walk(CARDS_DIR)
    .filter(p => exts.has(path.extname(p).toLowerCase()))
    .filter(p => p.split(path.sep).includes("thumbs"));

  const cards = [];
  for (const f of allFiles) {
    const ctx = parseCardContext(f);
    if (!ctx) continue;

    const filename = path.basename(f);
    const score = scoreFromFilename(filename);

    // Only include "good enough" cards in the pool
    if (score < 10) continue;

    cards.push({
      ...ctx,
      thumb: relPublic(f),
      score,
      filename
    });
  }

  // If you barely have any hits, lower the threshold above (score < 10)
  const payload = {
    generatedAt: new Date().toISOString(),
    count: cards.length,
    // Keep it reasonably sized. Most "good" cards will remain anyway.
    cards
  };

  fs.writeFileSync(OUT_FILE, JSON.stringify(payload, null, 2), "utf8");

  // Optional: print a sample pick
  const sample = cards.length ? weightedPick(cards) : null;
  console.log(`Wrote ${cards.length} good cards -> ${path.relative(ROOT, OUT_FILE)}`);
  if (sample) console.log("Sample pick:", sample.href, sample.thumb, "score", sample.score);
}

main();
