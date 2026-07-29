const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const {
  assertTrustedMacUpdateUrl,
  buildMacUpdateHelperScript,
  compareVersions,
  installedAppPathFromExecutable,
  parseSigningIdentities,
  selectLocalAppleSigningIdentity,
} = require("../macUpdater");

test("accepts only official Omniverse macOS release images", () => {
  const accepted =
    "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse-arm64.dmg";
  assert.equal(assertTrustedMacUpdateUrl(accepted).hostname, "github.com");

  for (const rejected of [
    "http://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.dmg",
    "https://example.com/Omniverse.dmg",
    "https://github.com/another/repo/releases/download/v1/Omniverse.dmg",
    "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.zip",
  ]) {
    assert.throws(() => assertTrustedMacUpdateUrl(rejected), /untrusted/);
  }
});

test("compares dotted release versions numerically", () => {
  assert.equal(compareVersions("2.1.80", "2.1.79"), 1);
  assert.equal(compareVersions("v2.1.79", "2.1.79"), 0);
  assert.equal(compareVersions("2.1.9", "2.1.10"), -1);
});

test("parses usable signing identities", () => {
  const output = `
  1) BEB0AC36EC62EFBE0478DF0F13D25B7E520D0D73 "Apple Development: developer@example.com (TEAM123)"
     1 valid identities found
  `;
  assert.deepEqual(parseSigningIdentities(output), [
    {
      hash: "BEB0AC36EC62EFBE0478DF0F13D25B7E520D0D73",
      name: "Apple Development: developer@example.com (TEAM123)",
    },
  ]);
});

test("prefers a local Apple Development identity", () => {
  const identities = [
    {
      hash: "A".repeat(40),
      name: "Developer ID Application: Release Developer (TEAM123)",
    },
    {
      hash: "B".repeat(40),
      name: "Apple Development: Local Developer (TEAM123)",
    },
  ];
  assert.equal(selectLocalAppleSigningIdentity(identities), identities[1]);
});

test("installer validates, rolls back, and explicitly relaunches", () => {
  const script = buildMacUpdateHelperScript();
  const syntax = spawnSync("/bin/sh", ["-n"], {
    input: script,
    encoding: "utf8",
  });
  assert.equal(syntax.status, 0, syntax.stderr);
  assert.match(script, /codesign --verify --deep --strict/);
  assert.match(script, /xattr -dr com\.apple\.quarantine/);
  assert.match(script, /CFBundleShortVersionString/);
  assert.match(script, /restore_backup/);
  assert.match(script, /open -n/);
});

test("derives the containing app bundle from its executable", () => {
  assert.equal(
    installedAppPathFromExecutable(
      "/Applications/Omniverse.app/Contents/MacOS/Omniverse",
    ),
    "/Applications/Omniverse.app",
  );
  assert.throws(
    () => installedAppPathFromExecutable("/tmp/electron"),
    /packaged macOS/,
  );
});
