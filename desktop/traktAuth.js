(function exposeTraktAuth(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.TraktAuth = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function createTraktAuth() {
  "use strict";

  const REDIRECT_URI = "omniplay://trakt/oauth";
  const credentialNoise = /[\s\u200B\u200C\u200D\u2060\uFEFF]/gu;

  function normalizeTraktCredential(value) {
    return String(value || "").replace(credentialNoise, "");
  }

  function buildTraktAuthorizeUrl(clientId, state) {
    const normalizedClientId = normalizeTraktCredential(clientId);
    if (!normalizedClientId) return null;
    const url = new URL("https://trakt.tv/oauth/authorize");
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", normalizedClientId);
    url.searchParams.set("redirect_uri", REDIRECT_URI);
    url.searchParams.set("state", String(state || ""));
    return url.toString();
  }

  function isTraktCredentialRejection(status) {
    return Number(status) === 401 || Number(status) === 403;
  }

  return {
    REDIRECT_URI,
    buildTraktAuthorizeUrl,
    isTraktCredentialRejection,
    normalizeTraktCredential,
  };
});
