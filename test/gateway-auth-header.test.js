import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("gateway auth header overwrites browser-supplied Basic credentials", () => {
  const src = fs.readFileSync(new URL("../src/server.js", import.meta.url), "utf8");
  const idx = src.indexOf("function attachGatewayAuthHeader");
  assert.ok(idx >= 0);
  const window = src.slice(idx, idx + 500);

  // Browsers attach stored Basic credentials to same-origin requests themselves,
  // including the websocket upgrade. Skipping injection when an Authorization
  // header is already present hands the gateway `Basic <setup password>` and the
  // Control UI dies with a token mismatch.
  assert.doesNotMatch(window, /!req\?\.headers\?\.authorization/);
  assert.match(window, /req\.headers\.authorization = `Bearer \$\{OPENCLAW_GATEWAY_TOKEN\}`/);

  // Webhook callers on /hooks authenticate as themselves and must be left alone.
  assert.match(window, /\/hooks/);
});
