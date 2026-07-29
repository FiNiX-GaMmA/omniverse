const test = require("node:test");
const assert = require("node:assert/strict");
const { hasLocalAppleSigningIdentity } = require("../scripts/afterPack");

test("detects usable local Apple signing identities", () => {
  assert.equal(
    hasLocalAppleSigningIdentity(
      '  1) BEB0AC36EC62EFBE0478DF0F13D25B7E520D0D73 "Apple Development: Local Developer (TEAM123)"',
    ),
    true,
  );
  assert.equal(
    hasLocalAppleSigningIdentity(
      '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Release Developer (TEAM123)"',
    ),
    true,
  );
  assert.equal(hasLocalAppleSigningIdentity("0 valid identities found"), false);
});
