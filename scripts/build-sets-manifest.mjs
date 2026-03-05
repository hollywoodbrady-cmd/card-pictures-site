import { S3Client, ListObjectsV2Command } from "@aws-sdk/client-s3";
import fs from "node:fs";
import path from "node:path";

const {
  R2_ACCOUNT_ID,
  R2_ACCESS_KEY_ID,
  R2_SECRET_ACCESS_KEY,
  R2_BUCKET,
  R2_PUBLIC_BASE,
} = process.env;

function need(name) {
  if (!process.env[name]) throw new Error(`Missing env var: ${name}`);
  return process.env[name];
}

need("R2_ACCOUNT_ID");
need("R2_ACCESS_KEY_ID");
need("R2_SECRET_ACCESS_KEY");
need("R2_BUCKET");
need("R2_PUBLIC_BASE");

const client = new S3Client({
  region: "auto",
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
  },
});

const bucket = R2_BUCKET;

// We only care about thumbs; full is optional.
const PREFIX = "cards/";
const THUMBS_SEGMENT = "/thumbs/";

async function listAllKeys(prefix) {
  const keys = [];
  let ContinuationToken = undefined;

  while (true) {
    const res = await client.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: prefix,
        ContinuationToken,
      })
    );

    for (const obj of res.Contents ?? []) {
      if (obj.Key) keys.push(obj.Key);
    }

    if (!res.IsTruncated) break;
    ContinuationToken = res.NextContinuationToken;
  }

  return keys;
}

const keys = await listAllKeys(PREFIX);

// Build structure: sports -> sets -> array of {thumb, full}
const manifest = {};
const base = R2_PUBLIC_BASE.replace(/\/$/, "");

for (const key of keys) {
  // Only thumbs images
  if (!key.includes(THUMBS_SEGMENT)) continue;
  if (!/\.(webp|jpg|jpeg|png|gif)$/i.test(key)) continue;

  // key: cards/<sport>/<set>/thumbs/<file>
  const parts = key.split("/");
  if (parts.length < 5) continue;

  const sport = parts[1];
  const set = parts[2];
  const file = parts.slice(4).join("/"); // in case subfolders

  const thumbUrl = `${base}/${key}`;
  const fullKey = `cards/${sport}/${set}/full/${file}`;
  const fullUrl = `${base}/${fullKey}`;

  manifest[sport] ??= {};
  manifest[sport][set] ??= [];
  manifest[sport][set].push({
    thumb: thumbUrl,
    full: fullUrl, // may 404 if you don't have full; we'll handle in UI
    file,
  });
}

// Optional: stable sort within each set by filename
for (const sport of Object.keys(manifest)) {
  for (const set of Object.keys(manifest[sport])) {
    manifest[sport][set].sort((a, b) => a.file.localeCompare(b.file));
  }
}

const outPath = path.join(process.cwd(), "public", "sets.json");
fs.writeFileSync(outPath, JSON.stringify({ generatedAt: new Date().toISOString(), manifest }, null, 2));
console.log(`Wrote sets manifest -> ${outPath}`);