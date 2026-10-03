# Next.js on Railcode, Path B: the app under `/api`

Use this when [the checks in the main guide](nextjs.md#which-path) say `"type": "next"` is not
available yet. It works on CLI 0.3.7 and was the path used for the app the guide was proven
on.

The idea: a Railcode server without `worker_routes` sends only `/api/*` to the worker and
serves everything else from the static tree. So the whole Next app is mounted at `/api`, its
hashed assets are served statically from `/static`, and a one-line `index.html` sends `/` and
deep links to `/api/...`.

Costs, so the user can decide: every page URL starts with `/api`, and the project carries
five small files of build plumbing. When Path A becomes available, delete them
([Moving to Path A](#moving-to-path-a)).

Do the code port from the main guide ([Porting the code](nextjs.md#porting-the-code-both-paths))
either before or after this; the two are independent.

## Files to add

```bash
npm install @railcode/sdk @opennextjs/cloudflare
npm install -D wrangler
```

**`railcode.json`** — no `"type"`: this is a bring-your-own build.

```json
{
  "app": "my-app",
  "build": "node railcode/build.mjs",
  "dist": "dist/client",
  "server": "dist/server/index.js",
  "dev": { "command": "node railcode/dev.mjs", "worker": "railcode/dev-proxy.mjs" }
}
```

**`package.json` scripts** — `build` stays `next build`. The adapter runs `npm run build`; if
`build` pointed at `railcode/build.mjs`, each build would start another and the machine would
run out of memory.

```json
{ "dev": "railcode dev", "build": "next build", "deploy": "railcode deploy" }
```

**`next.config.ts`**

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  basePath: "/api",          // the worker only receives /api/*
  assetPrefix: "/static",    // hashed assets come from the static tree, not the worker
  images: { unoptimized: true },
  turbopack: { root: import.meta.dirname },
  experimental: { cpus: 2 }, // keep `next build` from using every core
  async redirects() {
    // Dev parity: in production the static index.html sends / to /api.
    return [{ source: "/", destination: "/api", basePath: false, permanent: false }];
  },
};

export default nextConfig;
```

`assetPrefix` must be a real path. `"/"` makes Next emit `//_next/...`, which a browser reads
as another host.

Because of `basePath`, `<Link href="/todos">` and `redirect("/todos")` are prefixed for you,
but a hand-written `fetch("/todos/1/breakdown")` or `<a href>` is not. Write those as
`/api/...`.

**`wrangler.jsonc`** — read only by the adapter build. The date and flag must match the
platform's.

```jsonc
{
  "name": "my-app",
  "main": ".open-next/worker.js",
  "compatibility_date": "2026-06-01",
  "compatibility_flags": ["nodejs_compat"],
  "assets": { "directory": ".open-next/assets", "binding": "ASSETS" }
}
```

**`open-next.config.ts`**

```ts
import { defineCloudflareConfig } from "@opennextjs/cloudflare";

export default defineCloudflareConfig({});
```

**`railcode/entry.mjs`** — the worker the platform runs.

```js
import next from "../.open-next/worker.js";
import PRERENDERED from "./prerender-cache.generated.mjs";

// The adapter expects an ASSETS binding. The platform serves the static tree itself, so the
// only thing read through ASSETS is the prerender cache, which the build bundled.
const ASSETS = {
  async fetch(input) {
    const url = typeof input === "string" ? input : input.url;
    const body = PRERENDERED[decodeURIComponent(new URL(url).pathname)];
    return body === undefined
      ? new Response("Not found", { status: 404 })
      : new Response(body, { headers: { "content-type": "application/json" } });
  },
};

export default {
  async fetch(request, env, ctx) {
    // The request arrives with the platform's internal Host, while request.url is the public
    // URL (set by the platform, not the browser). Next compares Origin with the forwarded
    // host for Server Actions, so restate the real host. Both headers: the adapter overwrites
    // x-forwarded-host from Host.
    const publicHost = new URL(request.url).host;
    const headers = new Headers(request.headers);
    headers.set("host", publicHost);
    headers.set("x-forwarded-host", publicHost);
    return next.fetch(new Request(request, { headers }), { ...(env ?? {}), ASSETS }, ctx);
  },
};
```

**`railcode/build.mjs`**

```js
import { execSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

// The adapter builds Next by running package.json's "build". If that ever points back here,
// every level would start another build.
if (process.env.RAILCODE_NEXT_BUILD) {
  throw new Error('railcode/build.mjs re-entered — package.json "build" must be "next build"');
}
process.env.RAILCODE_NEXT_BUILD = "1";

const run = (cmd) => execSync(cmd, { stdio: "inherit" });
const BASE = "api"; // keep in sync with basePath in next.config.ts

rmSync("dist", { recursive: true, force: true });
run("npx opennextjs-cloudflare build");

// Bundle the prerender cache into the worker, keyed by the path the adapter asks ASSETS for.
const prerendered = {};
const walk = (dir) => {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else prerendered[`/cdn-cgi/_next_cache/${relative(".open-next/cache", full)}`] = readFileSync(full, "utf8");
  }
};
walk(".open-next/cache");
writeFileSync("railcode/prerender-cache.generated.mjs", `export default ${JSON.stringify(prerendered)};\n`);

// One self-contained module, resolved the way the runtime resolves it.
run("npx wrangler deploy railcode/entry.mjs --dry-run --minify --outdir dist/server --name app");
rmSync("dist/server/README.md", { force: true });
for (const f of readdirSync("dist/server")) if (f.endsWith(".map")) rmSync(`dist/server/${f}`);
renameSync("dist/server/entry.js", "dist/server/index.js");

// Static tree: public files at the root, hashed assets under /static.
mkdirSync("dist/client/static", { recursive: true });
cpSync(`.open-next/assets/${BASE}`, "dist/client", { recursive: true });
cpSync(`.open-next/assets/${BASE}/_next`, "dist/client/static/_next", { recursive: true });
rmSync("dist/client/_next", { recursive: true, force: true });
writeFileSync(
  "dist/client/index.html",
  // The platform falls back to index.html for any non-/api path, so this also turns a deep
  // link like /todos into /api/todos.
  `<!doctype html><meta charset="utf-8"><title>App</title>` +
    `<script>location.replace("/${BASE}" + (location.pathname === "/" ? "" : location.pathname) + location.search)</script>`,
);
```

If `dist/server` contains anything besides `index.js` after the build (a `.wasm`), the app
uses something that needs a second module. It will crash when deployed; remove that feature.

**`railcode/dev.mjs`** — starts `next dev` with the SDK's local credentials, which
`railcode dev` writes to `.dev.vars`.

```js
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

const vars = {};
for (const line of readFileSync(".dev.vars", "utf8").split(/\r?\n/)) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/i);
  if (m) vars[m[1]] = m[2];
}
const port = process.env.PORT ?? "5173";
mkdirSync("node_modules/.railcode", { recursive: true });
writeFileSync("node_modules/.railcode/next-port", port); // read by dev-proxy.mjs

const child = spawn("npx", ["next", "dev", "--port", port, "--hostname", "127.0.0.1"], {
  stdio: "inherit",
  env: { ...process.env, ...vars },
});
child.on("exit", (code) => process.exit(code ?? 0));
```

**`railcode/dev-proxy.mjs`** — `railcode dev` hosts this as the `/api/*` worker; it forwards to
`next dev`. The CLI bundles it for the browser platform, so `import "node:fs"` fails; reach
the builtin at runtime instead.

```js
const { readFileSync } = globalThis.process.getBuiltinModule("node:fs");

export default {
  async fetch(request) {
    const port = readFileSync("node_modules/.railcode/next-port", "utf8").trim();
    const url = new URL(request.url);
    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    return fetch(`http://127.0.0.1:${port}${url.pathname}${url.search}`, {
      method: request.method,
      headers: request.headers,
      body: hasBody ? await request.arrayBuffer() : undefined,
      redirect: "manual",
    });
  },
};
```

**`.gitignore`** — add `/.open-next`, `/dist`, `/.wrangler`, `.dev.vars`, `.railcode`,
`/railcode/prerender-cache.generated.mjs`.

## Limits specific to this path

- **Worker size limit is 5 MB.** A plain app is about 3 MB. Cache Components pushes it to about
  5.1 MB, and `proxy.ts`/middleware adds about 3 MB; either can put the upload over.
- **Caches are off by default.** With `defineCloudflareConfig({})` the incremental and tag
  caches are no-ops: statically prerendered pages still serve from the bundle, but
  `"use cache"`, the fetch cache and `revalidateTag`/`updateTag` do nothing. If the app depends
  on them, copy [nextjs-cache-adapter.ts](nextjs-cache-adapter.ts) into the project as
  `railcode/next-cache.ts` and wire it as its header shows. It stores entries in the app's
  store and registers every write with `ctx.waitUntil`; without that, a page hangs on every
  request after its first render.
- **Local harness for the real bundle.** `railcode dev` runs Next in Node. To run the built
  worker itself, start `railcode dev` for the data plane and, separately,
  `npx wrangler dev dist/server/index.js --no-bundle` with `RC_DEV_TOKEN` and
  `RC_DATA_PLANE_URL` from `.dev.vars` in its environment. Stop both when done.

## Moving to Path A

Once the three checks pass:

1. Delete `railcode/`, `wrangler.jsonc` and `open-next.config.ts` (keep the last only if it
   holds real overrides, rewritten with `defineRailcodeConfig`).
2. `npm uninstall @opennextjs/cloudflare wrangler && npm install -D @railcode/next`.
3. In `next.config.ts` remove `basePath`, `assetPrefix` and the `/` redirect.
4. Replace `railcode.json` with the following, keeping the app's existing slug:

   ```json
   { "app": "my-app", "type": "next", "dist": "dist/client", "server": "dist/server/index.js" }
   ```
5. Search the code for hand-written `/api/` URLs that were only there because of `basePath`
   and drop the prefix. Routes that really live under `app/api/` keep it. Cron handlers move
   the other way: `app/refresh/route.ts` becomes `app/api/refresh/route.ts`, so the manifest
   path `/api/refresh` still reaches it.
6. Deploy, then tell the people who use the app: every page URL just lost its `/api` prefix,
   so bookmarks to `/api/...` pages stop working.
