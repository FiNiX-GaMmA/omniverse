"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const {
  assertHttpUrl,
  assertSafeExternalUrl,
  assertTrustedDesktopUpdateUrl,
} = require("../securityPolicy");

const repoRoot = path.resolve(__dirname, "..", "..");

test("accepts only official platform-specific desktop release assets", () => {
  const base =
    "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/";
  assert.equal(
    assertTrustedDesktopUpdateUrl(`${base}Omniverse-arm64.dmg`, "darwin")
      .hostname,
    "github.com",
  );
  assert.doesNotThrow(() =>
    assertTrustedDesktopUpdateUrl(
      `${base}Omniverse%20Setup%20x64.exe`,
      "win32",
    ),
  );
  assert.doesNotThrow(() =>
    assertTrustedDesktopUpdateUrl(`${base}Omniverse-x64.AppImage`, "linux"),
  );

  for (const candidate of [
    "http://github.com/FiNiX-GaMmA/omniverse/releases/download/v2/Omniverse.dmg",
    "https://github.com.evil.example/FiNiX-GaMmA/omniverse/releases/download/v2/Omniverse.dmg",
    "https://github.com/another/repo/releases/download/v2/Omniverse.dmg",
    `${base}Omniverse-arm64.dmg?mirror=1`,
    `${base}Omniverse-arm64.dmg#download`,
    `${base}%2e%2e%2fOmniverse-arm64.dmg`,
    `${base}other-arm64.dmg`,
    `${base}Omniverse-arm64.zip`,
  ]) {
    assert.throws(
      () => assertTrustedDesktopUpdateUrl(candidate, "darwin"),
      /untrusted/,
      candidate,
    );
  }
});

test("limits external navigation and IPC requests to safe protocols", () => {
  assert.equal(
    assertSafeExternalUrl("https://trakt.tv/oauth/authorize?client_id=test")
      .hostname,
    "trakt.tv",
  );
  assert.throws(
    () => assertSafeExternalUrl("https://trakt.tv.evil.example/oauth"),
    /untrusted/,
  );
  assert.throws(
    () => assertSafeExternalUrl("javascript:alert(1)"),
    /invalid|untrusted/,
  );
  assert.doesNotThrow(() => assertHttpUrl("http://localhost:11470/stream"));
  assert.throws(() => assertHttpUrl("file:///etc/passwd"), /untrusted/);
  assert.throws(() => assertHttpUrl("https://user:pass@example.com"), /untrusted/);
});

test("keeps the main Electron window isolated from Node.js", () => {
  const source = fs.readFileSync(path.join(repoRoot, "desktop", "main.js"), "utf8");
  assert.match(source, /contextIsolation:\s*true/);
  assert.match(source, /nodeIntegration:\s*false/);
  assert.match(source, /sandbox:\s*true/);
  assert.doesNotMatch(source, /webSecurity:\s*false/);
});

test("tracked text files contain no recognizable private keys or provider tokens", () => {
  const allTracked = execFileSync("git", ["ls-files", "-z"], {
    cwd: repoRoot,
  })
    .toString("utf8")
    .split("\0")
    .filter(Boolean);
  assert.equal(allTracked.includes("android/keystore.properties"), false);
  assert.equal(allTracked.includes("keystore/omniverse-release.jks"), false);

  const tracked = allTracked
    .filter((file) =>
      /\.(?:js|json|kt|kts|swift|md|yml|yaml|plist|properties|gradle|txt|html|css)$/i.test(
        file,
      ),
    )
    .filter(
      (file) =>
        !file.startsWith("graphify-out/") &&
        file !== "desktop/package-lock.json",
    );
  const credentialPattern =
    /-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{20,}\b|\bxox[baprs]-[A-Za-z0-9-]{20,}\b/;
  const findings = tracked.filter((file) => {
    const content = fs.readFileSync(path.join(repoRoot, file), "utf8");
    return credentialPattern.test(content);
  });
  assert.deepEqual(findings, []);
});
