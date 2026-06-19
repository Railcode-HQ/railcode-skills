# Platform Magic

Use this reference when an agent needs to explain or rely on Railcode's zero-config auth, data, SDK, access, SQL, or LLM behavior.

## Request Routing

Railcode apps are static tools served from subdomains:

```text
https://<tool>.<BASE_DOMAIN>/
```

On the server, Caddy maps each tool host to a static folder:

```text
/var/www/tools/<tool>/
```

The same host also exposes the platform API at `/_api/*`. Because the browser calls same-origin URLs, app code does not need CORS configuration, API URLs, or credentials.

Reserved subdomains such as `auth`, `api`, `www`, and `admin` cannot be app names.

## Auth And Tool Identity

Railcode derives context from server-controlled request state:

- User identity comes from a signed session cookie validated by Caddy and the backend.
- Caddy strips any client-sent `X-User` header before forwarding.
- Caddy injects trusted identity headers after `forward_auth` verifies the session.
- Tool identity comes from the `Host` header, not from browser JavaScript.
- CLI/API-token routes use `/v1/apps/{app}/...`, making the app explicit in the path.

This is the core "magic": frontend code just calls `/_api/*`, and the backend knows both who is calling and which tool is calling.

## SDK Surface

Every tool can load:

```html
<script src="/_api/sdk.js"></script>
```

The SDK attaches globals:

```js
await me();
await toolUsers();
await db.collection("items").put("key", { ok: true });
await db.collection("items").get("key");
await files.upload("name.png", blob, "image/png");
await connections();
await sql("select * from orders where id = $1", [id]);
await llm.generate("Summarize this record.", { metadata: { feature: "summary" } });
```

The SDK also mounts a live inspector drawer that shows SDK activity. Do not hide SDK errors; surface useful error states in the app.

## Access Policies

A tool without an access policy is closed until first deploy creates public
access for signed-in users. Configure access later in the admin UI.

Modes:

- `private`: owner-only unless additional owner/user grants are created.
- `workspace`: available to authenticated workspace users.
- `restricted`: available only to named users or domains.

`toolUsers()` returns the current mode, known users, and whether the roster is complete. Restricted or domain-based access may not produce a complete roster; treat `complete: false` as "known users only".

## KV Store

`db.collection(name)` is a per-tool JSON key/value store. It is shared across that tool's allowed users.

Use shared keys for shared collaboration surfaces:

```js
await db.collection("messages").put(messageId, message);
```

Use user-prefixed keys for per-user private state:

```js
const identity = await me();
await db.collection("drafts").put(`${identity.user}:${draftId}`, draft);
```

There is no server-side query language for KV. `list()` returns rows for the collection; filter, sort, and page in the app.

## Files

Files are per-tool objects:

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
      properties: {
        status: { type: "string", enum: ["healthy", "risk", "unknown"] },
        reason: { type: "string" }
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

Use `llm.stream()` for incremental text output. Include metadata for audit trails. Expect global daily token caps, provider timeouts, input limits, and structured-output validation to be enforced server-side.

## Local Dev Bridge

`railcode dev` preserves the same SDK calling style in local development:

- Identity is `local-dev`.
- Tool users report `mode: "local"`.
- KV/files are local files under `~/.railcode/dev/<tool>`.
- SQL, connections, and LLM forward to the configured Railcode backend only when the CLI has a saved API token.

This lets agents build most app behavior without a live server and add production-backed SQL/LLM only when credentials and access are available.
