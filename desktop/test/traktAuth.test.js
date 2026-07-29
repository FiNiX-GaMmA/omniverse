"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  REDIRECT_URI,
  buildTraktAuthorizeUrl,
  isTraktCredentialRejection,
  normalizeTraktCredential,
} = require("../traktAuth");

test("normalizes whitespace and invisible clipboard characters in Trakt credentials", () => {
  assert.equal(
    normalizeTraktCredential("  abcd\u200B ef\n12\uFEFF34  "),
    "abcdef1234",
  );
});

test("builds an authorization URL with a non-empty normalized client_id", () => {
  const url = new URL(
    buildTraktAuthorizeUrl(" abcd\u200B1234 ", "state-token"),
  );
  assert.equal(url.origin + url.pathname, "https://trakt.tv/oauth/authorize");
  assert.equal(url.searchParams.get("response_type"), "code");
  assert.equal(url.searchParams.get("client_id"), "abcd1234");
  assert.equal(url.searchParams.get("redirect_uri"), REDIRECT_URI);
  assert.equal(url.searchParams.get("state"), "state-token");
});

test("recognizes statuses that require a fresh Trakt session", () => {
  assert.equal(isTraktCredentialRejection(401), true);
  assert.equal(isTraktCredentialRejection(403), true);
  assert.equal(isTraktCredentialRejection(429), false);
});
