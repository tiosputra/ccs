---
name: ai-regression-testing
description: Regression coverage for the mistakes AI-written code actually repeats - a field added to one code path but not its twin (production vs sandbox, detail vs list, handler vs query projection, HTTP vs socket), and bugs that come back after being fixed. Use after fixing a bug, or when a response shape changed and more than one path produces it.
metadata:
  origin: ECC
---

# AI Regression Testing

Testing patterns specifically designed for AI-assisted development, where the same model writes code and reviews it — creating systematic blind spots that only automated tests can catch.

## Repo rules first

If the repo being changed carries an `AGENTS.md` at its root, read it before
applying anything below, and follow it wherever the two disagree. It was written
for that codebase; this file was not. Where it is silent, this skill applies.
See `CLAUDE.md`.

## Twins in the repo you are in

The examples below come from a Next.js + Supabase + Vitest project. The repo you are in
may look nothing like that. The *patterns* transfer exactly; the code does not. Read the
snippets as illustrations of a failure mode, never as something to copy in.

Which twin paths exist in *this* repo is a fact about it, measured once: read the
`## Twin paths` section of `.claude/learned/<repo>/tdd-workflow.md` (the `tdd-workflow`
skill says how to check it is fresh, and `/learn tdd-workflow <repo>` writes it). Where
the repo has no sandbox mode, the "production path vs sandbox path" pattern shows up as a
different pair of twins. These are the ones that diverge most often:

| Twin paths | Why it goes wrong |
|---|---|
| A detail route and the list route returning the same object | A field is added to one shape, and the other is never opened |
| An HTTP response and a socket or event payload carrying the same object | The emitter builds its own object, far from the handler |
| An ORM projection (`attributes:`, a `SELECT` list) and the response built from it | The field is written into the response and arrives `undefined`, with no type error |
| A Go struct and its `json:` tags | A new field serializes under a name nobody agreed to, or not at all |

**The path nothing describes is the worst blind spot.** A REST change eventually shows up
in a generated spec someone reads; a socket or event payload is built in a handler no
consumer will ever open, and often nothing generates a description of it. When a change
touches an object that such an emitter also sends, that emit site is the path most likely
to be missed - grep for the field there before declaring the work done.

The rest of the skill - write the test where the bug was, name it after the bug, run the
suite before the review rather than after - applies unchanged.

## When to Activate

- AI agent (Claude Code, Cursor, Codex) has modified API routes or backend logic
- A bug was found and fixed — need to prevent re-introduction
- Project has a sandbox/mock mode that can be leveraged for DB-free testing
- Running `tdd-workflow`'s blind-spot pass (Step 7b), or the review step after it
- Multiple code paths exist (sandbox vs production, feature flags, etc.)

## The Core Problem

When an AI writes code and then reviews its own work, it carries the same assumptions into both steps. This creates a predictable failure pattern:

```
AI writes fix → AI reviews fix → AI says "looks correct" → Bug still exists
```

**Real-world example** (observed in production):

```
Fix 1: Added notification_settings to API response
  → Forgot to add it to the SELECT query
  → AI reviewed and missed it (same blind spot)

Fix 2: Added it to SELECT query
  → TypeScript build error (column not in generated types)
  → AI reviewed Fix 1 but didn't catch the SELECT issue

Fix 3: Changed to SELECT *
  → Fixed production path, forgot sandbox path
  → AI reviewed and missed it AGAIN (4th occurrence)

Fix 4: Test caught it instantly on first run PASS:
```

The pattern: **sandbox/production path inconsistency** is the #1 AI-introduced regression.

## Sandbox-Mode API Testing

Most projects with AI-friendly architecture have a sandbox/mock mode. This is the key to fast, DB-free API testing.

### Setup (Vitest + Next.js App Router)

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  test: {
    environment: "node",
    globals: true,
    include: ["__tests__/**/*.test.ts"],
    setupFiles: ["__tests__/setup.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
});
```

```typescript
// __tests__/setup.ts
// Force sandbox mode — no database needed
process.env.SANDBOX_MODE = "true";
process.env.NEXT_PUBLIC_SUPABASE_URL = "";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "";
```

### Test Helper for Next.js API Routes

```typescript
// __tests__/helpers.ts
import { NextRequest } from "next/server";

export function createTestRequest(
  url: string,
  options?: {
    method?: string;
    body?: Record<string, unknown>;
    headers?: Record<string, string>;
    sandboxUserId?: string;
  },
): NextRequest {
  const { method = "GET", body, headers = {}, sandboxUserId } = options || {};
  const fullUrl = url.startsWith("http") ? url : `http://localhost:3000${url}`;
  const reqHeaders: Record<string, string> = { ...headers };

  if (sandboxUserId) {
    reqHeaders["x-sandbox-user-id"] = sandboxUserId;
  }

  const init: { method: string; headers: Record<string, string>; body?: string } = {
    method,
    headers: reqHeaders,
  };

  if (body) {
    init.body = JSON.stringify(body);
    reqHeaders["content-type"] = "application/json";
  }

  return new NextRequest(fullUrl, init);
}

export async function parseResponse(response: Response) {
  const json = await response.json();
  return { status: response.status, json };
}
```

### Writing Regression Tests

The key principle: **write tests for bugs that were found, not for code that works**.

```typescript
// __tests__/api/user/profile.test.ts
import { describe, it, expect } from "vitest";
import { createTestRequest, parseResponse } from "../../helpers";
import { GET, PATCH } from "@/app/api/user/profile/route";

// Define the contract — what fields MUST be in the response
const REQUIRED_FIELDS = [
  "id",
  "email",
  "full_name",
  "phone",
  "role",
  "created_at",
  "avatar_url",
  "notification_settings",  // ← Added after bug found it missing
];

describe("GET /api/user/profile", () => {
  it("returns all required fields", async () => {
    const req = createTestRequest("/api/user/profile");
    const res = await GET(req);
    const { status, json } = await parseResponse(res);

    expect(status).toBe(200);
    for (const field of REQUIRED_FIELDS) {
      expect(json.data).toHaveProperty(field);
    }
  });

  // Regression test — this exact bug was introduced by AI 4 times
  it("notification_settings is not undefined (BUG-R1 regression)", async () => {
    const req = createTestRequest("/api/user/profile");
    const res = await GET(req);
    const { json } = await parseResponse(res);

    expect("notification_settings" in json.data).toBe(true);
    const ns = json.data.notification_settings;
    expect(ns === null || typeof ns === "object").toBe(true);
  });
});
```

### Testing Sandbox/Production Parity

The most common AI regression: fixing production path but forgetting sandbox path (or vice versa).

```typescript
// Test that sandbox responses match the expected contract
describe("GET /api/user/messages (conversation list)", () => {
  it("includes partner_name in sandbox mode", async () => {
    const req = createTestRequest("/api/user/messages", {
      sandboxUserId: "user-001",
    });
    const res = await GET(req);
    const { json } = await parseResponse(res);

    // This caught a bug where partner_name was added
    // to production path but not sandbox path
    if (json.data.length > 0) {
      for (const conv of json.data) {
        expect("partner_name" in conv).toBe(true);
      }
    }
  });
});
```

## Where this runs in the flow

There is no separate bug-check command here: the same sequence is already built into
the build.

1. **Tests and build first, mechanically.** `tdd-workflow`'s Step 7 runs the repo's
   whole suite and its build; a failure there is a bug found with no judgment needed.
2. **Then the known blind spots.** `tdd-workflow`'s Step 7b, the blind-spot pass, walks
   the patterns below against the diff — twin paths first.
3. **Every fix gets its regression test**, written RED first like any other change, so
   the next run catches it if the fix breaks.
4. **Then review.** `/plan-prd`'s review step dispatches the language reviewers, which
   catch what the patterns miss.

## Common AI Regression Patterns

### Pattern 1: Sandbox/Production Path Mismatch

**Frequency**: Most common (observed in 3 out of 4 regressions)

```typescript
// FAIL: AI adds field to production path only
if (isSandboxMode()) {
  return { data: { id, email, name } };  // Missing new field
}
// Production path
return { data: { id, email, name, notification_settings } };

// PASS: Both paths must return the same shape
if (isSandboxMode()) {
  return { data: { id, email, name, notification_settings: null } };
}
return { data: { id, email, name, notification_settings } };
```

**Test to catch it**:

```typescript
it("sandbox and production return same fields", async () => {
  // In test env, sandbox mode is forced ON
  const res = await GET(createTestRequest("/api/user/profile"));
  const { json } = await parseResponse(res);

  for (const field of REQUIRED_FIELDS) {
    expect(json.data).toHaveProperty(field);
  }
});
```

### Pattern 2: SELECT Clause Omission

**Frequency**: Common with Supabase/Prisma when adding new columns

```typescript
// FAIL: New column added to response but not to SELECT
const { data } = await supabase
  .from("users")
  .select("id, email, name")  // notification_settings not here
  .single();

return { data: { ...data, notification_settings: data.notification_settings } };
// → notification_settings is always undefined

// PASS: Use SELECT * or explicitly include new columns
const { data } = await supabase
  .from("users")
  .select("*")
  .single();
```

### Pattern 3: Error State Leakage

**Frequency**: Moderate — when adding error handling to existing components

```typescript
// FAIL: Error state set but old data not cleared
catch (err) {
  setError("Failed to load");
  // reservations still shows data from previous tab!
}

// PASS: Clear related state on error
catch (err) {
  setReservations([]);  // Clear stale data
  setError("Failed to load");
}
```

### Pattern 4: Optimistic Update Without Proper Rollback

```typescript
// FAIL: No rollback on failure
const handleRemove = async (id: string) => {
  setItems(prev => prev.filter(i => i.id !== id));
  await fetch(`/api/items/${id}`, { method: "DELETE" });
  // If API fails, item is gone from UI but still in DB
};

// PASS: Capture previous state and rollback on failure
const handleRemove = async (id: string) => {
  const prevItems = [...items];
  setItems(prev => prev.filter(i => i.id !== id));
  try {
    const res = await fetch(`/api/items/${id}`, { method: "DELETE" });
    if (!res.ok) throw new Error("API error");
  } catch {
    setItems(prevItems);  // Rollback
    alert("削除に失敗しました");
  }
};
```

## Strategy: Test Where Bugs Were Found

Don't aim for 100% coverage. Instead:

```
Bug found in /api/user/profile     → Write test for profile API
Bug found in /api/user/messages    → Write test for messages API
Bug found in /api/user/favorites   → Write test for favorites API
No bug in /api/user/notifications  → Don't write test (yet)
```

**Why this works with AI development:**

1. AI tends to make the **same category of mistake** repeatedly
2. Bugs cluster in complex areas (auth, multi-path logic, state management)
3. Once tested, that exact regression **cannot happen again**
4. Test count grows organically with bug fixes — no wasted effort

## Quick Reference

| AI Regression Pattern | Test Strategy | Priority |
|---|---|---|
| Sandbox/production mismatch | Assert same response shape in sandbox mode |  High |
| SELECT clause omission | Assert all required fields in response |  High |
| Error state leakage | Assert state cleanup on error |  Medium |
| Missing rollback | Assert state restored on API failure |  Medium |
| Type cast masking null | Assert field is not undefined |  Medium |

## DO / DON'T

**DO:**
- Write tests immediately after finding a bug (before fixing it if possible)
- Test the API response shape, not the implementation
- Run tests as the first step of every blind-spot pass
- Keep tests fast (< 1 second total with sandbox mode)
- Name tests after the bug they prevent (e.g., "BUG-R1 regression")

**DON'T:**
- Write tests for code that has never had a bug
- Trust AI self-review as a substitute for automated tests
- Skip sandbox path testing because "it's just mock data"
- Write integration tests when unit tests suffice
- Aim for coverage percentage — aim for regression prevention
