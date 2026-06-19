# App Patterns

Use this reference when implementing a Railcode app UI, data model, SDK calls, or local validation.

## Starter Layout

`railcode init <tool>` creates:

```text
railcode.json
package.json
vite.config.ts
src/
  App.tsx
  main.tsx
  styles.css
  lib/
    load-sdk.ts
    railcode.ts
    format.ts
  store/
    app-store.ts
  components/
    Button.tsx
    Panel.tsx
    StatusPill.tsx
dist/
```

`railcode.json` names the app and asset dev port:

```json
{
  "app": "my-tool",
  "dev": {
    "root": ".",
    "port": 5173
  }
}
```

`vite.config.ts` builds to `dist/`. Do not change the output path unless the deploy layout also changes.

## Loading The SDK

The starter loads the SDK dynamically:

```ts
await loadRailcodeSdk();
```

Then it calls typed wrappers:

```ts
import { collection, fileStore, getIdentity, llm, runSql } from "@/lib/railcode";
```

Prefer the wrappers over direct `window.*` use. If creating a non-starter app, include either the dynamic loader or an HTML script tag before the app bundle:

```html
<script src="/_api/sdk.js"></script>
```

Fail clearly when SDK globals are unavailable. This usually means the app is being served directly by Vite instead of through `railcode dev`, or the platform SDK has not been built/bundled.

## UI Expectations

Railcode apps are internal tools. Build the actual working interface as the first screen, not a marketing page. Favor dense, readable, task-focused layouts with clear states for loading, empty data, errors, and successful writes.

Do not add custom auth screens. Users should arrive authenticated through the platform. Use `me()` only to show identity or namespace data.

Do not leak platform internals such as bearer tokens, DSNs, LLM provider config, or admin-only settings into browser state.

## State And Data Modeling

Use Zustand or local React state for client state. Keep persisted data in Railcode KV/files/SQL depending on the use case:

- Use KV for app-owned JSON records, preferences, drafts, and lightweight collaboration state.
- Use files for binary uploads or generated artifacts.
- Use SQL for read-only views over external Postgres data configured by an admin.
- Use LLM for summarization, classification, drafting, or structured extraction when configured.

Define collection names and key formats explicitly near the API/store layer:

```ts
const TASKS_COLLECTION = "tasks";
const taskKey = (id: string) => id;
const userTaskKey = (user: string, id: string) => `${user}:${id}`;
```

If data is per-user, prefix by `identity.user`. If data is shared, make conflict behavior obvious in the UI.

## KV Pattern

```ts
type Task = {
  id: string;
  title: string;
  done: boolean;
  updatedAt: string;
};

const tasks = collection<Task>("tasks");

await tasks.put(task.id, task);
const saved = await tasks.get(task.id);
const rows = await tasks.list();
await tasks.delete(task.id);
```

`list()` returns rows shaped like `{ key, value, updated_at }`. Sort by fields inside `value` when the app needs deterministic ordering.

## File Pattern

```ts
await fileStore.upload(file.name, file, file.type || "application/octet-stream");
const entries = await fileStore.list();
const url = fileStore.url(file.name);
```

Keep file names flat. For names that originate from users, normalize or generate a stable ID and store the display name in KV.

## SQL Pattern

```ts
const rows = await runSql(
  "select id, name, status from customers where status = $1 order by name limit 100",
  [status],
  "analytics",
);
```

Use user-selected filters only as params. Show a useful empty state when `connections()` is empty or a connection is not configured.

## LLM Pattern

Text:

```ts
const result = await llm.generate(
  [
    { role: "system", content: "Write concise operational summaries." },
    { role: "user", content: noteText },
  ],
  {
    maxOutputTokens: 300,
    metadata: { feature: "note-summary", object_type: "note", object_id: noteId },
  },
);
```

Structured output:

```ts
const result = await llm.generate(prompt, {
  output: {
    type: "json",
    schema: {
      type: "object",
      properties: {
        priority: { type: "string", enum: ["low", "medium", "high"] },
        reason: { type: "string" }
      },
      required: ["priority", "reason"]
    }
  },
  metadata: { feature: "priority-classifier" },
});
```

Render provider errors and token-cap failures as normal app states. Do not retry indefinitely.

## Build And Check

For app-only work:

```bash
npm run build
```

If dependency install is needed, `railcode dev` installs missing deps automatically, but an explicit `npm install` or `npm ci` may still be useful before a build.

If the app depends on SQL or LLM, test local no-backend behavior and logged-in backend behavior separately when credentials are available:

```bash
railcode dev --reset --verbose
RAILCODE_API_URL=https://auth.tools.example.com RAILCODE_API_TOKEN=<token> railcode dev --verbose
railcode dev --verbose
```

## Common Pitfalls

- Opening the Vite URL directly bypasses `/_api/sdk.js`; use the `railcode dev` URL.
- Editing `dist/` directly is lost on the next build.
- First deploy creates public access for signed-in users.
- Using un-namespaced KV keys accidentally shares private data across users.
- Treating `toolUsers().users` as a complete roster when `complete` is false.
- String-concatenating SQL user input creates injection risk even though transactions are read-only.
- Assuming LLM is always enabled; it requires provider settings and a global daily token cap.
