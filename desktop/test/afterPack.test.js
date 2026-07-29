const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  collectCodeTargets,
  hasLocalAppleSigningIdentity,
  sortCodeTargetsInsideOut,
} = require("../scripts/afterPack");

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
  assert.equal(typeof collectCodeTargets, "function");
  const entitlements = fs.readFileSync(
    path.join(__dirname, "..", "entitlements.mac.plist"),
    "utf8",
  );
  assert.match(entitlements, /com\.apple\.security\.cs\.allow-jit/);
});

test("signs nested Electron helpers before their enclosing bundles", () => {
  const app = path.join(path.sep, "tmp", "Omniverse.app");
  const framework = path.join(
    app,
    "Contents",
    "Frameworks",
    "Electron Framework.framework",
  );
  const frameworkBinary = path.join(
    framework,
    "Versions",
    "A",
    "Electron Framework",
  );
  const crashpad = path.join(
    framework,
    "Versions",
    "A",
    "Helpers",
    "chrome_crashpad_handler",
  );
  const helperApp = path.join(
    app,
    "Contents",
    "Frameworks",
    "Omniverse Helper.app",
  );
  const helperBinary = path.join(
    helperApp,
    "Contents",
    "MacOS",
    "Omniverse Helper",
  );

  const ordered = sortCodeTargetsInsideOut(
    [app, framework, frameworkBinary, crashpad, helperApp, helperBinary, crashpad],
    app,
  );

  assert.equal(ordered.at(-1), app);
  assert.equal(ordered.filter((target) => target === crashpad).length, 1);
  assert.ok(ordered.indexOf(crashpad) < ordered.indexOf(frameworkBinary));
  assert.ok(ordered.indexOf(frameworkBinary) < ordered.indexOf(framework));
  assert.ok(ordered.indexOf(helperBinary) < ordered.indexOf(helperApp));
});
