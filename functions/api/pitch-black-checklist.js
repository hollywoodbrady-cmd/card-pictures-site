const ALLOWED_USERS = new Set(["Isabella", "Haley"]);
const DEFAULT_DISPLAY_NAMES = Object.freeze({ Isabella: "Isabella", Haley: "Haley" });
const DEFAULT_AVATARS = Object.freeze({ Isabella: "eevee", Haley: "red-panda-face" });
const AVATAR_PRESETS = new Set(["red-panda-face","red-panda-body","red-panda-sleepy","red-panda-berry","eevee","pikachu","vulpix","jigglypuff","mew","togepi","teddiursa","skitty","piplup","minccino","emolga","rowlet","rockruff","yamper","sprigatito","pawmi"]);
const MAX_CUSTOM_AVATAR_LENGTH = 300000;
const PIN_ENV = {
  Isabella: "PITCH_BLACK_PIN_ISABELLA",
  Haley: "PITCH_BLACK_PIN_HALEY"
};
const CHECKLISTS = new Set(["pitch-black", "tepig-line"]);
const TEPIG_LINE_IDS = new Set(["tepig-bwp-bw02", "tepig-mcd11-3", "tepig-mcd21-13", "tepig-bw1-15", "tepig-bw1-16", "tepig-bw11-25", "tepig-bwp-bw07", "tepig-bw7-24", "tepig-sm12-31", "tepig-swsh5-23", "tepig-swshp-swsh172", "tepig-wht-11", "tepig-wht-96", "tepig-asc-29", "tepig-mep-50", "pignite-bw1-17", "pignite-mcd12-4", "pignite-bw1-18", "pignite-bw11-26", "pignite-bw7-25", "pignite-sm12-32", "pignite-swsh5-24", "pignite-wht-12", "pignite-wht-97", "pignite-asc-30", "emboar-bw1-19", "emboar-bw1-20", "emboar-bwp-bw21", "emboar-bw4-100", "emboar-bw11-27", "emboar-bw7-26", "emboar-sm12-33", "emboar-swsh5-25", "emboar-wht-13", "emboar-wht-98", "emboar-xy9-14", "mega-emboar-asc-31", "mega-emboar-asc-273", "mega-emboar-mep-35"]);
const VALID_STATUSES = new Set(["have", "need"]);
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;
const MAX_LOGIN_ATTEMPTS = 8;
const LOGIN_WINDOW_SECONDS = 10 * 60;
const MAX_ACTIVITY = 100;
const encoder = new TextEncoder();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
}
function validUser(user) { return typeof user === "string" && ALLOWED_USERS.has(user); }
function validChecklist(checklist) { return typeof checklist === "string" && CHECKLISTS.has(checklist); }
function validCardId(checklist, id) {
  if (checklist === "pitch-black") return /^\d{3}$/.test(id) && Number(id) >= 1 && Number(id) <= 120;
  return checklist === "tepig-line" && TEPIG_LINE_IDS.has(id);
}
function allCardIds(checklist) {
  if (checklist === "pitch-black") return Array.from({ length: 120 }, (_, index) => String(index + 1).padStart(3, "0"));
  return checklist === "tepig-line" ? [...TEPIG_LINE_IDS] : [];
}
function withDefaultNeeds(checklist, explicitStatuses = {}) {
  const statuses = Object.fromEntries(allCardIds(checklist).map(id => [id, "need"]));
  for (const [id, value] of Object.entries(explicitStatuses || {})) statuses[id] = value === "have" || value === "duplicate" ? "have" : "need";
  return statuses;
}
function storageKey(checklist, user) { return checklist === "pitch-black" ? `pitch-black:${user}` : `tepig-line:${user}`; }
function activityKey(checklist) { return `pokemon-checklists:activity:${checklist}`; }
function displayNameKey(user) { return `pokemon-checklists:display-name:${user}`; }
function avatarKey(user) { return `pokemon-checklists:avatar:${user}`; }
function cleanDisplayName(value) {
  if (typeof value !== "string") return null;
  const name = value.trim().replace(/\s+/g, " ");
  if (!name || [...name].length > 30 || /[\u0000-\u001F\u007F]/.test(name)) return null;
  return name;
}
async function getDisplayNames(context) {
  const pairs = await Promise.all([...ALLOWED_USERS].map(async user => {
    const saved = await context.env.PITCH_BLACK_CHECKLIST.get(displayNameKey(user));
    return [user, cleanDisplayName(saved) || DEFAULT_DISPLAY_NAMES[user] || user];
  }));
  return Object.fromEntries(pairs);
}
function cleanAvatar(value, user) {
  if (value?.kind === "preset" && AVATAR_PRESETS.has(value.id)) return { kind: "preset", id: value.id };
  if (value?.kind === "custom" && typeof value.dataUrl === "string" && value.dataUrl.length <= MAX_CUSTOM_AVATAR_LENGTH && /^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/i.test(value.dataUrl)) return { kind: "custom", dataUrl: value.dataUrl };
  return { kind: "preset", id: DEFAULT_AVATARS[user] };
}
async function getAvatars(context) {
  const pairs = await Promise.all([...ALLOWED_USERS].map(async user => {
    const saved = await context.env.PITCH_BLACK_CHECKLIST.get(avatarKey(user), { type: "json" });
    return [user, cleanAvatar(saved, user)];
  }));
  return Object.fromEntries(pairs);
}
function cleanStatuses(checklist, statuses, owned) {
  const out = {};
  if (statuses && typeof statuses === "object" && !Array.isArray(statuses)) {
    const entries = Object.entries(statuses); if (entries.length > 200) return null;
    for (const [rawId, value] of entries) {
      const id = String(rawId);
      if (!validCardId(checklist, id)) return null;
      // v8 migration: old Duplicate / trade entries still represent an owned card; all other valid cards default to Need.
      if (value === "duplicate") out[id] = "have";
      else if (VALID_STATUSES.has(value)) out[id] = value;
      else return null;
    }
    return out;
  }
  if (Array.isArray(owned)) {
    if (owned.length > 200) return null;
    for (const rawId of owned) { const id = String(rawId); if (validCardId(checklist, id)) out[id] = "have"; }
    return out;
  }
  return {};
}
function ownedFromStatuses(statuses) { return Object.entries(statuses).filter(([,s]) => s === "have").map(([id]) => id).sort(); }
function normalizeRecord(user, checklist, raw) {
  const explicit = cleanStatuses(checklist, raw?.statuses, raw?.owned) || {};
  const statuses = withDefaultNeeds(checklist, explicit);
  return { user, checklist, statuses, owned: ownedFromStatuses(statuses), lastSaved: raw?.lastSaved || null, lastSavedBy: validUser(raw?.lastSavedBy) ? raw.lastSavedBy : (raw?.lastSaved ? user : null) };
}
function bytesToBase64Url(bytes) { let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte); return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, ""); }
function textToBase64Url(text) { return bytesToBase64Url(encoder.encode(text)); }
function base64UrlToBytes(value) { const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4); const binary = atob(padded); return Uint8Array.from(binary, c => c.charCodeAt(0)); }
function base64UrlToText(value) { return new TextDecoder().decode(base64UrlToBytes(value)); }
function safeEqualBytes(a, b) { if (!(a instanceof Uint8Array) || !(b instanceof Uint8Array) || a.length !== b.length) return false; let diff = 0; for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]; return diff === 0; }
async function hashText(value) { return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))); }
async function safeEqualText(a, b) { return safeEqualBytes(await hashText(String(a)), await hashText(String(b))); }
async function hmac(secret, value) { const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]); return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(value))); }
async function issueToken(user, secret) { const now = Math.floor(Date.now() / 1000); const payload = textToBase64Url(JSON.stringify({ user, iat: now, exp: now + TOKEN_TTL_SECONDS })); const signature = bytesToBase64Url(await hmac(secret, payload)); return `${payload}.${signature}`; }
async function verifyToken(token, secret) {
  try { if (typeof token !== "string") return null; const [payloadPart, signaturePart, extra] = token.split("."); if (!payloadPart || !signaturePart || extra) return null; const expected = await hmac(secret, payloadPart); const supplied = base64UrlToBytes(signaturePart); if (!safeEqualBytes(expected, supplied)) return null; const payload = JSON.parse(base64UrlToText(payloadPart)); const now = Math.floor(Date.now() / 1000); if (!validUser(payload.user) || !Number.isFinite(payload.exp) || payload.exp <= now) return null; return payload; } catch { return null; }
}
function authHeaderToken(request) { const header = request.headers.get("Authorization") || ""; const match = header.match(/^Bearer\s+(.+)$/i); return match ? match[1] : null; }
function attemptKey(context, user) { const ip = context.request.headers.get("CF-Connecting-IP") || "unknown"; return `pokemon-checklists:auth-attempts:${user}:${ip}`; }
async function login(context, body) {
  const { user, pin } = body || {}; if (!validUser(user)) return json({ error: "Invalid user" }, 400); if (typeof pin !== "string" || pin.length < 1 || pin.length > 100) return json({ error: "PIN required" }, 400);
  const secret = context.env.PITCH_BLACK_AUTH_SECRET, expectedPin = context.env[PIN_ENV[user]]; if (!secret || !expectedPin) return json({ error: "Authentication is not configured" }, 503);
  const key = attemptKey(context, user); const failures = Number(await context.env.PITCH_BLACK_CHECKLIST.get(key) || "0"); if (failures >= MAX_LOGIN_ATTEMPTS) return json({ error: "Too many incorrect attempts. Try again later." }, 429);
  if (!(await safeEqualText(pin, expectedPin))) { await context.env.PITCH_BLACK_CHECKLIST.put(key, String(failures + 1), { expirationTtl: LOGIN_WINDOW_SECONDS }); return json({ error: "Invalid PIN" }, 401); }
  await context.env.PITCH_BLACK_CHECKLIST.delete(key); return json({ ok: true, user, token: await issueToken(user, secret), expiresIn: TOKEN_TTL_SECONDS });
}
async function getRecord(context, checklist, user) { const raw = await context.env.PITCH_BLACK_CHECKLIST.get(storageKey(checklist, user), { type: "json" }); return normalizeRecord(user, checklist, raw); }
async function renameProfile(context, auth, body) {
  const { user } = body || {};
  if (!validUser(user)) return json({ error: "Invalid user" }, 400);
  if (auth.user !== user) return json({ error: "You can only change your own name" }, 403);
  const displayName = cleanDisplayName(body?.displayName);
  if (!displayName) return json({ error: "Name must be 1 to 30 characters" }, 400);

  const names = await getDisplayNames(context);
  const duplicate = Object.entries(names).some(([otherUser, otherName]) =>
    otherUser !== user && otherName.toLocaleLowerCase() === displayName.toLocaleLowerCase()
  );
  if (duplicate) return json({ error: "That name is already being used" }, 409);

  await context.env.PITCH_BLACK_CHECKLIST.put(displayNameKey(user), displayName);
  return json({ ok: true, user, displayName });
}
async function updateAvatar(context, auth, body) {
  const { user } = body || {};
  if (!validUser(user)) return json({ error: "Invalid user" }, 400);
  if (auth.user !== user) return json({ error: "You can only change your own profile picture" }, 403);
  const avatar = cleanAvatar(body?.avatar, user);
  const supplied = body?.avatar;
  if (!supplied || (supplied.kind === "preset" && !AVATAR_PRESETS.has(supplied.id)) || (supplied.kind === "custom" && (typeof supplied.dataUrl !== "string" || supplied.dataUrl.length > MAX_CUSTOM_AVATAR_LENGTH || !/^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/i.test(supplied.dataUrl)))) return json({ error: "Invalid profile picture" }, 400);
  await context.env.PITCH_BLACK_CHECKLIST.put(avatarKey(user), JSON.stringify(avatar));
  return json({ ok: true, user, avatar });
}

async function appendActivity(context, checklist, entries) {
  if (!entries.length) return;
  let existing = await context.env.PITCH_BLACK_CHECKLIST.get(activityKey(checklist), { type: "json" }); if (!Array.isArray(existing)) existing = [];
  await context.env.PITCH_BLACK_CHECKLIST.put(activityKey(checklist), JSON.stringify([...entries, ...existing].slice(0, MAX_ACTIVITY)));
}

export async function onRequestGet(context) {
  if (!context.env.PITCH_BLACK_CHECKLIST) return json({ error: "KV binding missing" }, 503);
  const url = new URL(context.request.url); const checklist = url.searchParams.get("checklist") || "pitch-black";
  if (!validChecklist(checklist)) return json({ error: "Invalid checklist" }, 400);
  if (url.searchParams.get("activity") === "1") {
    const [activity, displayNames, avatars] = await Promise.all([context.env.PITCH_BLACK_CHECKLIST.get(activityKey(checklist), { type: "json" }), getDisplayNames(context), getAvatars(context)]); return json({ checklist, activity: Array.isArray(activity) ? activity : [], displayNames, avatars });
  }
  if (url.searchParams.get("all") === "1") {
    const [pairs, displayNames, avatars] = await Promise.all([Promise.all([...ALLOWED_USERS].map(async user => [user, await getRecord(context, checklist, user)])), getDisplayNames(context), getAvatars(context)]); return json({ checklist, collections: Object.fromEntries(pairs), displayNames, avatars });
  }
  const user = url.searchParams.get("user"); if (!validUser(user)) return json({ error: "Invalid user" }, 400); const [record, displayNames, avatars] = await Promise.all([getRecord(context, checklist, user), getDisplayNames(context), getAvatars(context)]); return json({ ...record, displayName: displayNames[user], avatar: avatars[user] });
}

export async function onRequestPost(context) {
  if (!context.env.PITCH_BLACK_CHECKLIST) return json({ error: "KV binding missing" }, 503);
  let body; try { body = await context.request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (body?.action === "login") return login(context, body);
  const secret = context.env.PITCH_BLACK_AUTH_SECRET; if (!secret) return json({ error: "Authentication is not configured" }, 503);
  const auth = await verifyToken(authHeaderToken(context.request), secret); if (!auth) return json({ error: "Unlock required" }, 401);
  if (body?.action === "rename") return renameProfile(context, auth, body);
  if (body?.action === "avatar") return updateAvatar(context, auth, body);
  const { user, checklist = "pitch-black" } = body || {}; if (!validUser(user)) return json({ error: "Invalid user" }, 400); if (!validChecklist(checklist)) return json({ error: "Invalid checklist" }, 400); if (auth.user !== user) return json({ error: "You can only edit your own checklist" }, 403);
  const cleanedStatuses = cleanStatuses(checklist, body.statuses, body.owned); if (!cleanedStatuses) return json({ error: "Invalid card status data" }, 400);
  const statuses = withDefaultNeeds(checklist, cleanedStatuses);
  const previous = await getRecord(context, checklist, user); const now = new Date().toISOString();
  const record = { user, checklist, statuses, owned: ownedFromStatuses(statuses), lastSaved: now, lastSavedBy: user };
  await context.env.PITCH_BLACK_CHECKLIST.put(storageKey(checklist, user), JSON.stringify(record));
  const ids = new Set([...Object.keys(previous.statuses), ...Object.keys(statuses)]); const changes = [];
  for (const cardId of ids) {
    const from = previous.statuses[cardId] === "have" ? "have" : "need", to = statuses[cardId] === "have" ? "have" : "need";
    if (from !== to) changes.push({ id: crypto.randomUUID(), user, checklist, cardId, from, to, at: now });
  }
  await appendActivity(context, checklist, changes.slice(0, 40));
  return json({ ok: true, ...record, changed: changes.length });
}
