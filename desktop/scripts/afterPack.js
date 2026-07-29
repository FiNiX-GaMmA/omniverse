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
const path = require("path");

function hasLocalAppleSigningIdentity(output) {
  return /^\s*\d+\)\s+[A-F0-9]{40}\s+"(?:Apple Development|Developer ID Application):/im.test(
    String(output || ""),
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
    execFileSync("/usr/bin/codesign", [
      "--force",
      "--deep",
      "--options",
      "runtime",
      "--preserve-metadata=identifier,entitlements,flags,runtime",
      "--timestamp=none",
      "--sign",
      match[1],
      appPath,
    ], { stdio: "inherit" });
    console.log(
      "[afterPack] signed with local Apple identity:",
      appPath,
    );
    return;
  }

  try {
    execFileSync("/usr/bin/codesign", [
      "--force",
      "--deep",
      "--sign",
      "-",
      appPath,
    ], {
      stdio: "inherit",
    });
    console.log("[afterPack] ad-hoc signed:", appPath);
  } catch (e) {
    console.warn("[afterPack] ad-hoc sign failed:", e.message);
  }
};

exports.hasLocalAppleSigningIdentity = hasLocalAppleSigningIdentity;
