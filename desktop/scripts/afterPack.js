// electron-builder afterPack hook.
//
// Ad-hoc code-signs the macOS app so it launches on Apple Silicon even when the
// build runner has no Apple Developer identity (as on GitHub's macOS runners).
// Unsigned arm64 binaries are refused by macOS with "…is not supported on this
// Mac." An ad-hoc signature (`codesign -s -`) makes the app runnable; Gatekeeper
// then shows the normal "unidentified developer" prompt, which the user bypasses
// via right-click > Open (or by clearing the quarantine attribute).
//
// Runs before electron-builder's own signing step, so if a real identity IS
// present (e.g. a local dev machine) that signature overwrites this one.

const { execSync } = require("child_process");
const path = require("path");

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== "darwin") return;
  const appName = context.packager.appInfo.productFilename;
  const appPath = path.join(context.appOutDir, `${appName}.app`);
  try {
    execSync(`codesign --force --deep --sign - "${appPath}"`, {
      stdio: "inherit",
    });
    console.log("[afterPack] ad-hoc signed:", appPath);
  } catch (e) {
    console.warn("[afterPack] ad-hoc sign failed:", e.message);
  }
};
