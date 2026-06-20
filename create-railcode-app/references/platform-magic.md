# Platform Magic

Use this reference when an agent needs to explain or rely on Railcode's zero-config auth, data, SDK, access, SQL, or LLM behavior.

## Request Routing

Railcode apps are static apps served from subdomains:

```text
https://<app>.<BASE_DOMAIN>/
```

On the server, Caddy maps each app host to a static folder:

```text
/srv/apps/<app>/
```

The same host also exposes the platform API at `/_api/*`. Because the browser calls same-origin URLs, app code does not need CORS configuration, API URLs, or credentials.

Reserved subdomains such as `auth`, `api`, `www`, and `admin` cannot be app names.

## Auth And App Identity

Railcode derives context from server-controlled request state:

- User identity comes from a signed session cookie validated by Caddy and the backend.
- Caddy strips any client-sent `X-User` header before forwarding.
- Caddy injects trusted identity headers after `forward_auth` verifies the session.
- App identity comes from the `Host` header, not from browser JavaScript.
- CLI/API-token routes use `/v1/apps/{app}/...`, making the app explicit in the path.

This is the core "magic": frontend code just calls `/_api/*`, and the backend knows both who is calling and which app is calling.

## SDK Surface

Every app can load:

```html
<script src="/_api/sdk.js"></script>
```

The SDK attaches globals:

```js
await me();
await appUsers();
await db.collection("items").put("key", { ok: true });
await db.collection("items").get("key");
await files.upload("name.png", blob, "image/png");
await connections();
await sql("select * from orders where id = $1", [id]);
await llm.generate("Summarize this record.", { metadata: { feature: "summary" } });
```

The SDK also ships a live inspector drawer that logs SDK activity (every `db`,
`sql`, `llm`, `files`, `me()`, `appUsers()` call). It is hidden by default and
has no on-screen affordance, so end users never see it; toggle it open with
`Cmd+L` (mac) / `Ctrl+L` while developing. Do not hide SDK errors; surface
useful error states in the app.

## Access Policies

An app without an access policy is closed until first deploy creates public
access for signed-in users. Configure access later in the admin UI.

Modes:

- `private`: owner-only unless additional owner/user grants are created.
- `workspace`: available to authenticated workspace users.
- `restricted`: available only to named users or domains.

`appUsers()` returns the current mode, known users, and whether the roster is complete. Restricted or domain-based access may not produce a complete roster; treat `complete: false` as "known users only".

## KV Store

`db.collection(name)` is a per-app JSON key/value store. It is shared across that app's allowed users.

Use shared keys for shared collaboration surfaces:

```js
await db.collection("messages").put(messageId, message);
```

Use user-prefixed keys for per-user private state:

```js
const identity = await me();
await db.collection("drafts").put(`${identity.user}:${draftId}`, draft);
```

Use the query builder when a collection can grow beyond a small in-memory list:

```js
const page = await db.collection("messages")
  .where("roomId", "==", roomId)
  .orderBy("updatedAt", "desc")
  .page(1, { size: 50 });

const mine = await db.collection("drafts").prefix(`${identity.user}:`).page();
const changed = await db.collection("messages").updatedSince(lastSeenIso).count();
```

`where()` filters on JSON paths inside the stored value and supports `==`, `!=`,
`>`, `>=`, `<`, `<=`, and `in`. `prefix()`, `updatedSince()`, and
`updatedBefore()` filter indexed row metadata. `list()` still returns all rows
for compatibility; prefer `page()`, `first()`, or `count()` for large
collections.

## Files

Files are per-app objects:

```js
await files.upload("logo.png", blob, "image/png");
const url = files.url("logo.png");
const entries = await files.list();
await files.delete("logo.png");
```

File API names cannot contain `/`. If an app needs folders, store a flat file name and model logical hierarchy in KV metadata.

## SQL

An admin registers global Postgres connections in the admin UI. Browser apps call `sql()` without seeing DSNs or passwords:

```js
const rows = await sql(
  "select id, total from orders where customer_id = $1",
  [customerId],
  { connection: "analytics" },
);
```

Rules:

- Treat SQL as read-only.
- Always use `$1`, `$2`, ... placeholders and a params array.
- Never concatenate user input into SQL.
- Call `connections()` to discover configured connection names.
- Expect `connections()` to be empty in unauthenticated local dev.

## LLM

LLM setup is admin-controlled. Apps do not choose providers, models, or API keys. They call:

```js
const result = await llm.generate("Classify this customer.", {
  output: {
    type: "json",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        status: { type: "string", enum: ["healthy", "risk", "unknown"] },
        reason: { type: ["string", "null"] }
      },
      required: ["status", "reason"]
    }
  },
  metadata: {
    feature: "customer-health",
    object_type: "customer",
    object_id: customerId
  }
});
```

JSON schemas run in OpenAI strict mode: every object must set
`additionalProperties: false` and list **all** of its keys in `required`. Make
optional fields nullable (`{ type: ["string", "null"] }`) instead of omitting
them from `required`. Non-compliant schemas are rejected up front with
`invalid_schema` (the message names the offending path). See `docs/llm-api-v0.md`.

Use `llm.stream()` for incremental text output. Include metadata for audit trails. Expect global daily token caps, provider timeouts, input limits, and structured-output validation to be enforced server-side.

## Local Dev Bridge

`railcode dev` preserves the same SDK calling style in local development:

- Identity is `local-dev`.
- App users report `mode: "local"`.
- KV/files are local files under `~/.railcode/dev/<app>`, and the KV query
  builder (`where`/`prefix`/`orderBy`/`page`/`first`/`count`) runs against them
  with the same semantics as production.
- SQL, connections, and LLM forward to the configured Railcode backend only when the CLI has a saved API token.

On startup `railcode dev` prints whether backend-backed APIs (LLM, SQL) are
forwarding to the real API or will `401` for lack of a token, so you don't have
to fire a request to find out.

This lets agents build most app behavior without a live server and add production-backed SQL/LLM only when credentials and access are available.
