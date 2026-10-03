// Path B only (see nextjs-under-api.md). Copy this file to railcode/next-cache.ts in the
// project and wire it in open-next.config.ts:
//
//   import { defineCloudflareConfig } from "@opennextjs/cloudflare";
//   import { railcodeIncrementalCache, railcodeTagCache } from "./railcode/next-cache";
//   export default defineCloudflareConfig({
//     incrementalCache: async () => railcodeIncrementalCache,
//     tagCache: async () => railcodeTagCache,
//   });
//
// On Path A, @railcode/next ships this and wires it for you.
//
// Next.js caches backed by Railcode, for OpenNext.
//
// - Page prerenders ("cache" entries) are read-only build output. They're bundled
//   into the worker and served through OpenNext's static-assets cache (see the
//   ASSETS stand-in in railcode/entry.mjs).
// - "use cache" (composable) and fetch-cache entries are written at runtime, so
//   they live in the app's store via @railcode/sdk: shared by every isolate and
//   every user, surviving cold starts.
// - Tags (cacheTag / updateTag / revalidateTag) are a "nextMode" tag cache in the
//   store: one record per tag holding when it was last revalidated.
//
// All of this runs inside a Railcode invocation (the SDK's ambient context), on a
// request or in its waitUntil.
import { ctx, db } from "@railcode/sdk";
import staticAssetsCache from "@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache";
import type { IncrementalCache, NextModeTagCache } from "@opennextjs/aws/types/overrides.js";

const entries = db.collection<{ value: unknown; lastModified: number }>("next_cache");
const tags = db.collection<{ revalidatedAt: number; stale: number; expire: number | null }>("next_tags");

// Cache keys embed the build id, function id and serialized args, so they can be
// long. Hash them into fixed-size KV keys.
async function kvKey(kind: string, key: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${kind}:${key}`));
  return `${kind}:${[...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

export const railcodeIncrementalCache: IncrementalCache = {
  name: "railcode-kv-incremental-cache",
  async get(key, cacheType) {
    if (!cacheType || cacheType === "cache") return staticAssetsCache.get(key, cacheType);
    try {
      const row = await entries.get(await kvKey(cacheType, key));
      return row ? ({ value: row.value, lastModified: row.lastModified } as never) : null;
    } catch (e) {
      console.error("[next-cache] get failed", e);
      return null;
    }
  },
  async set(key, value, cacheType) {
    if (!cacheType || cacheType === "cache") return; // prerenders are read-only
    try {
      // Register the whole write, hashing included, before the first await.
      await keepAlive(
        kvKey(cacheType, key).then((k) => entries.put(k, { value, lastModified: Date.now() })),
      );
    } catch (e) {
      console.error("[next-cache] set failed", e);
    }
  },
  async delete(key) {
    for (const kind of ["composable", "fetch"]) await entries.delete(await kvKey(kind, key)).catch(() => {});
  },
};

// Next's implicit tags look like "_N_T_/team/layout"; slashes aren't valid in a
// Railcode KV key path, so store tags under a base64url form of the name.
const tagKey = (tag: string) =>
  btoa(String.fromCharCode(...new TextEncoder().encode(tag))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

// Next writes "use cache" entries after the response has streamed, and nothing
// ties that write to the invocation. On Railcode the invocation then ends and its
// unfinished I/O is dropped, so the entry is never stored. Older OpenNext
// versions also kept pending writes in an isolate-wide map that later requests
// awaited, so every following request for that key on the same isolate hung.
// Registering each write with the invocation's waitUntil lets it finish.
function keepAlive<T>(work: Promise<T>): Promise<T> {
  try {
    ctx.waitUntil(work);
  } catch {
    // outside an invocation (e.g. build): nothing to extend
  }
  return work;
}

// One KV read per tag per invocation: OpenNext asks about the same tags several
// times while serving one PPR page (shell, then resume). Same idea as the
// per-request cache in OpenNext's D1 tag cache.
type TagRow = { revalidatedAt: number; stale: number; expire: number | null };

// A tag whose record could not be read. It must count as revalidated: treating
// an unreadable tag as "never revalidated" would keep serving an entry that an
// updateTag() was meant to drop.
const UNREADABLE = Symbol("unreadable");
type TagRead = TagRow | null | typeof UNREADABLE;

const memo = new Map<string, Promise<TagRead>>();

// The invocation to memoize under, or null when there is none to scope to (the
// build, or a local run where every request shares one id): a memo that
// outlived its request would hide revalidations made by other requests.
const invocation = (): string | null => {
  try {
    const id = ctx.invocationId;
    return id && id !== "dev" ? id : null;
  } catch {
    return null;
  }
};

const readTag = (tag: string): Promise<TagRead> =>
  tags.get(tagKey(tag)).then(
    (found): TagRead => found ?? null,
    (e): TagRead => {
      console.error("[next-cache] tag read failed", e);
      return UNREADABLE;
    },
  );

async function readTags(names: string[]): Promise<TagRead[]> {
  const id = invocation();
  if (id === null) return Promise.all(names.map(readTag));
  if (memo.size > 500) memo.clear();
  return Promise.all(
    names.map((t) => {
      const k = `${id}:${t}`;
      let row = memo.get(k);
      if (!row) {
        row = readTag(t);
        memo.set(k, row);
        // A failed read is retried by the next caller, not remembered.
        void row.then((read) => {
          if (read === UNREADABLE) memo.delete(k);
        });
      }
      return row;
    }),
  );
}

export const railcodeTagCache: NextModeTagCache = {
  name: "railcode-kv-tag-cache",
  mode: "nextMode",
  async getLastRevalidated(names) {
    if (names.length === 0) return 0;
    const rows = await readTags(names);
    if (rows.includes(UNREADABLE)) return Date.now();
    return Math.max(0, ...rows.map((r) => (r as TagRow | null)?.revalidatedAt ?? 0));
  },
  async hasBeenRevalidated(names, lastModified) {
    if (names.length === 0) return false;
    const now = Date.now();
    return (await readTags(names)).some((r) => {
      if (r === UNREADABLE) return true;
      if (!r) return false;
      if (r.expire != null) return r.expire <= now && r.expire > (lastModified ?? 0);
      return r.revalidatedAt > (lastModified ?? now);
    });
  },
  async isStale(names, lastModified) {
    if (names.length === 0) return false;
    const now = Date.now();
    const lastModifiedOrNow = lastModified ?? now;
    // Same rule as OpenNext's D1 tag cache: stale when the tag was revalidated
    // after this entry was written, inside its stale window, and not yet expired.
    // An unreadable tag is not "stale" (serve-then-refresh): hasBeenRevalidated
    // already drops the entry.
    return (await readTags(names)).some(
      (r) =>
        r != null &&
        r !== UNREADABLE &&
        r.revalidatedAt > lastModifiedOrNow &&
        lastModifiedOrNow <= r.stale &&
        (r.expire == null || r.expire > now),
    );
  },
  async writeTags(input) {
    const now = Date.now();
    await keepAlive(Promise.all(
      input.map((t) => {
        const tag = typeof t === "string" ? t : t.tag;
        const stale = typeof t === "string" ? now : (t.stale ?? now);
        const expire = typeof t === "string" ? null : (t.expire ?? null);
        const id = invocation();
        if (id !== null) memo.delete(`${id}:${tag}`);
        return tags.put(tagKey(tag), { revalidatedAt: stale, stale, expire });
      }),
    ));
  },
};
