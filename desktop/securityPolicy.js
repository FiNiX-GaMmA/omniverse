"use strict";

const OFFICIAL_RELEASE_PREFIX =
  "/FiNiX-GaMmA/omniverse/releases/download/";

function parseHttpsUrl(rawUrl, label) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch (_) {
    throw new Error(`Refusing an invalid ${label} URL`);
  }
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.hash
  ) {
    throw new Error(`Refusing an untrusted ${label} URL`);
  }
  return url;
}

function assertTrustedDesktopUpdateUrl(rawUrl, platform) {
  const url = parseHttpsUrl(rawUrl, "desktop update");
  const extensionByPlatform = {
    darwin: [".dmg"],
    win32: [".exe"],
    linux: [".appimage", ".deb"],
  };
  const allowedExtensions = extensionByPlatform[platform];
  if (!allowedExtensions) {
    throw new Error(`Unsupported desktop update platform: ${platform}`);
  }

  let decodedPath;
  try {
    decodedPath = decodeURIComponent(url.pathname);
  } catch (_) {
    throw new Error("Refusing an untrusted desktop update URL");
  }
  const relativePath = decodedPath.slice(OFFICIAL_RELEASE_PREFIX.length);
  const pathParts = relativePath.split("/");
  const fileName = pathParts[1] || "";
  const lowerName = fileName.toLowerCase();

  if (
    url.hostname !== "github.com" ||
    url.search ||
    /%(?:00|2e|2f|5c)/i.test(url.pathname) ||
    !decodedPath.startsWith(OFFICIAL_RELEASE_PREFIX) ||
    pathParts.length !== 2 ||
    !pathParts[0] ||
    !lowerName.startsWith("omniverse") ||
    !allowedExtensions.some((extension) => lowerName.endsWith(extension))
  ) {
    throw new Error("Refusing an untrusted desktop update URL");
  }
  return url;
}

function assertSafeExternalUrl(rawUrl) {
  const url = parseHttpsUrl(rawUrl, "external navigation");
  const allowedHosts = new Set(["trakt.tv", "github.com"]);
  if (!allowedHosts.has(url.hostname)) {
    throw new Error("Refusing an untrusted external navigation URL");
  }
  return url;
}

function assertHttpUrl(rawUrl, label = "network request") {
  let url;
  try {
    url = new URL(rawUrl);
  } catch (_) {
    throw new Error(`Refusing an invalid ${label} URL`);
  }
  if (
    !["http:", "https:"].includes(url.protocol) ||
    url.username ||
    url.password
  ) {
    throw new Error(`Refusing an untrusted ${label} URL`);
  }
  return url;
}

module.exports = {
  OFFICIAL_RELEASE_PREFIX,
  assertHttpUrl,
  assertSafeExternalUrl,
  assertTrustedDesktopUpdateUrl,
};
