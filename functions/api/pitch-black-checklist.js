const ALLOWED_USERS = new Set(["Isabella", "Haley", "Friend 2", "Friend 3?"]);
const PIN_ENV = {
  Isabella: "PITCH_BLACK_PIN_ISABELLA",
  Haley: "PITCH_BLACK_PIN_HALEY",
  "Friend 2": "PITCH_BLACK_PIN_FRIEND_2",
  "Friend 3?": "PITCH_BLACK_PIN_FRIEND_3"
};

const CHECKLISTS = new Set(["pitch-black", "tepig-line"]);
const TEPIG_LINE_IDS = new Set(["tepig-bwp-bw02", "tepig-mcd11-3", "tepig-mcd21-13", "tepig-bw1-15", "tepig-bw1-16", "tepig-bw11-25", "tepig-bwp-bw07", "tepig-bw7-24", "tepig-sm12-31", "tepig-swsh5-23", "tepig-swshp-swsh172", "tepig-wht-11", "tepig-wht-96", "tepig-asc-29", "tepig-mep-50", "pignite-bw1-17", "pignite-mcd12-4", "pignite-bw1-18", "pignite-bw11-26", "pignite-bw7-25", "pignite-sm12-32", "pignite-swsh5-24", "pignite-wht-12", "pignite-wht-97", "pignite-asc-30", "emboar-bw1-19", "emboar-bw1-20", "emboar-bwp-bw21", "emboar-bw4-100", "emboar-bw11-27", "emboar-bw7-26", "emboar-sm12-33", "emboar-swsh5-25", "emboar-wht-13", "emboar-wht-98", "emboar-xy9-14", "mega-emboar-asc-31", "mega-emboar-asc-273", "mega-emboar-mep-35"]);
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;
const MAX_LOGIN_ATTEMPTS = 8;
const LOGIN_WINDOW_SECONDS = 10 * 60;
const encoder = new TextEncoder();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store"
    }
  });
}

function validUser(user) {
  return typeof user === "string" && ALLOWED_USERS.has(user);
}

function validChecklist(checklist) {
  return typeof checklist === "string" && CHECKLISTS.has(checklist);
}

function storageKey(checklist, user) {
  // Keep the original Pitch Black key format so existing saved Pitch Black data survives.
  return checklist === "pitch-black" ? `pitch-black:${user}` : `tepig-line:${user}`;
}

function cleanOwned(checklist, owned) {
  if (!Array.isArray(owned) || owned.length > 200) return null;

  if (checklist === "pitch-black") {
    return [...new Set(
      owned.map(String).filter(id => /^\d{3}$/.test(id) && Number(id) >= 1 && Number(id) <= 120)
    )].sort();
  }

  if (checklist === "tepig-line") {
    return [...new Set(owned.map(String).filter(id => TEPIG_LINE_IDS.has(id)))].sort();
  }

  return null;
}

function bytesToBase64Url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function textToBase64Url(text) {
  return bytesToBase64Url(encoder.encode(text));
}

function base64UrlToBytes(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

function base64UrlToText(value) {
  return new TextDecoder().decode(base64UrlToBytes(value));
}

function safeEqualBytes(a, b) {
  if (!(a instanceof Uint8Array) || !(b instanceof Uint8Array) || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function hashText(value) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

async function safeEqualText(a, b) {
  return safeEqualBytes(await hashText(String(a)), await hashText(String(b)));
}

async function hmac(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

async function issueToken(user, secret) {
  const now = Math.floor(Date.now() / 1000);
  const payload = textToBase64Url(JSON.stringify({ user, iat: now, exp: now + TOKEN_TTL_SECONDS }));
  const signature = bytesToBase64Url(await hmac(secret, payload));
  return `${payload}.${signature}`;
}

async function verifyToken(token, secret) {
  try {
    if (typeof token !== "string") return null;
    const [payloadPart, signaturePart, extra] = token.split(".");
    if (!payloadPart || !signaturePart || extra) return null;

    const expected = await hmac(secret, payloadPart);
    const supplied = base64UrlToBytes(signaturePart);
    if (!safeEqualBytes(expected, supplied)) return null;

    const payload = JSON.parse(base64UrlToText(payloadPart));
    const now = Math.floor(Date.now() / 1000);
    if (!validUser(payload.user) || !Number.isFinite(payload.exp) || payload.exp <= now) return null;
    return payload;
  } catch {
    return null;
  }
}

function authHeaderToken(request) {
  const header = request.headers.get("Authorization") || "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function attemptKey(context, user) {
  const ip = context.request.headers.get("CF-Connecting-IP") || "unknown";
  return `pokemon-checklists:auth-attempts:${user}:${ip}`;
}

async function login(context, body) {
  const { user, pin } = body || {};
  if (!validUser(user)) return json({ error: "Invalid user" }, 400);
  if (typeof pin !== "string" || pin.length < 1 || pin.length > 100) return json({ error: "PIN required" }, 400);

  const secret = context.env.PITCH_BLACK_AUTH_SECRET;
  const expectedPin = context.env[PIN_ENV[user]];
  if (!secret || !expectedPin) return json({ error: "Authentication is not configured" }, 503);

  const key = attemptKey(context, user);
  const failures = Number(await context.env.PITCH_BLACK_CHECKLIST.get(key) || "0");
  if (failures >= MAX_LOGIN_ATTEMPTS) {
    return json({ error: "Too many incorrect attempts. Try again later." }, 429);
  }

  if (!(await safeEqualText(pin, expectedPin))) {
    await context.env.PITCH_BLACK_CHECKLIST.put(key, String(failures + 1), { expirationTtl: LOGIN_WINDOW_SECONDS });
    return json({ error: "Invalid PIN" }, 401);
  }

  await context.env.PITCH_BLACK_CHECKLIST.delete(key);
  const token = await issueToken(user, secret);
  return json({ ok: true, user, token, expiresIn: TOKEN_TTL_SECONDS });
}

export async function onRequestGet(context) {
  const url = new URL(context.request.url);
  const user = url.searchParams.get("user");
  const checklist = url.searchParams.get("checklist") || "pitch-black";

  if (!validUser(user)) return json({ error: "Invalid user" }, 400);
  if (!validChecklist(checklist)) return json({ error: "Invalid checklist" }, 400);
  if (!context.env.PITCH_BLACK_CHECKLIST) return json({ error: "KV binding missing" }, 503);

  const saved = await context.env.PITCH_BLACK_CHECKLIST.get(storageKey(checklist, user), { type: "json" });
  return json(saved || { user, checklist, owned: [], lastSaved: null });
}

export async function onRequestPost(context) {
  if (!context.env.PITCH_BLACK_CHECKLIST) return json({ error: "KV binding missing" }, 503);

  let body;
  try {
    body = await context.request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  if (body?.action === "login") return login(context, body);

  const secret = context.env.PITCH_BLACK_AUTH_SECRET;
  if (!secret) return json({ error: "Authentication is not configured" }, 503);

  const auth = await verifyToken(authHeaderToken(context.request), secret);
  if (!auth) return json({ error: "Unlock required" }, 401);

  const { user, checklist = "pitch-black", owned, lastSaved } = body || {};
  if (!validUser(user)) return json({ error: "Invalid user" }, 400);
  if (!validChecklist(checklist)) return json({ error: "Invalid checklist" }, 400);
  if (auth.user !== user) return json({ error: "You can only edit your own checklist" }, 403);

  const cleaned = cleanOwned(checklist, owned);
  if (!cleaned) return json({ error: "Invalid owned-card list" }, 400);

  const record = {
    user,
    checklist,
    owned: cleaned,
    lastSaved: typeof lastSaved === "string" ? lastSaved : new Date().toISOString()
  };

  await context.env.PITCH_BLACK_CHECKLIST.put(storageKey(checklist, user), JSON.stringify(record));
  return json({ ok: true, ...record });
}
