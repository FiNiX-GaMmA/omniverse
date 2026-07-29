// electron-builder afterPack hook.
//
// Ad-hoc code-signs the macOS app so it launches on Apple Silicon even when the
// build runner has no Apple Developer identity (as on GitHub's macOS runners).
// Unsigned arm64 binaries are refused by macOS with "…is not supported on this
// Mac." An ad-hoc signature (`codesign -s -`) makes the app runnable; Gatekeeper
// then shows the normal "unidentified developer" prompt, which the user bypasses
// via right-click > Open (or by clearing the quarantine attribute).
//
// This hook owns the signing pass. package.json disables electron-builder's
// second signing pass so nested Electron frameworks are never signed twice.

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

function hasLocalAppleSigningIdentity(output) {
  return /^\s*\d+\)\s+[A-F0-9]{40}\s+"(?:Apple Development|Developer ID Application):/im.test(
    String(output || ""),
  );
}

function isMachO(filePath) {
  try {
    return execFileSync("/usr/bin/file", ["-b", filePath], {
      encoding: "utf8",
    }).includes("Mach-O");
  } catch (_) {
    return false;
  }
}

function collectCodeTargets(appPath) {
  const targets = [];

  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const target = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        visit(target);
        if (entry.name.endsWith(".framework") || entry.name.endsWith(".app")) {
          targets.push(target);
        }
      } else if (entry.isFile() && isMachO(target)) {
        targets.push(target);
      }
    }
  }

  visit(appPath);
  targets.push(appPath);
  return [...new Set(targets)];
}

function hasCodeSignature(target) {
  try {
    execFileSync("/usr/bin/codesign", ["--display", target], {
      stdio: "ignore",
    });
    return true;
  } catch (_) {
    return false;
  }
}

function needsElectronEntitlements(target) {
  return (
    target.endsWith(".app") ||
    target.includes(`${path.sep}Contents${path.sep}MacOS${path.sep}`)
  );
}

function signCodeTarget(target, identity, entitlementsPath) {
  const args = ["--force"];
  const addEntitlements =
    identity !== "-" && needsElectronEntitlements(target);
  if (identity !== "-") args.push("--options", "runtime");
  if (hasCodeSignature(target)) {
    args.push(
      addEntitlements
        ? "--preserve-metadata=identifier,flags,runtime"
        : "--preserve-metadata=identifier,entitlements,flags,runtime",
    );
  }
  if (addEntitlements) {
    args.push("--entitlements", entitlementsPath);
  }
  args.push("--timestamp=none", "--sign", identity, target);
  execFileSync("/usr/bin/codesign", args, { stdio: "inherit" });
}

function signAppInsideOut(appPath, identity) {
  const entitlementsPath = path.join(
    __dirname,
    "..",
    "entitlements.mac.plist",
  );
  for (const target of collectCodeTargets(appPath)) {
    signCodeTarget(target, identity, entitlementsPath);
  }
  execFileSync(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", "--verbose=2", appPath],
    { stdio: "inherit" },
  );
}

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== "darwin") return;
  const appName = context.packager.appInfo.productFilename;
  const appPath = path.join(context.appOutDir, `${appName}.app`);

  // Prefer the local Apple identity. It produces the same signature that the
  // in-app updater applies after downloading a release image.
  let identities = "";
  try {
    identities = execFileSync("/usr/bin/security", [
      "find-identity",
      "-v",
      "-p",
      "codesigning",
    ], { encoding: "utf8" });
  } catch (_) {
    // A runner without the security tool falls through to ad-hoc signing.
  }

  if (hasLocalAppleSigningIdentity(identities)) {
    const match = identities.match(
      /^\s*\d+\)\s+([A-F0-9]{40})\s+"(?:Apple Development|Developer ID Application):/im,
    );
    signAppInsideOut(appPath, match[1]);
    console.log(
      "[afterPack] signed with local Apple identity:",
      appPath,
    );
    return;
  }

  signAppInsideOut(appPath, "-");
  console.log("[afterPack] ad-hoc signed:", appPath);
};

exports.hasLocalAppleSigningIdentity = hasLocalAppleSigningIdentity;
exports.collectCodeTargets = collectCodeTargets;
