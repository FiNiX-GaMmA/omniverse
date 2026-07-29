---
type: "query"
date: "2026-07-29T06:07:29.298886+00:00"
question: "How does Omniverse preserve Android upgrade compatibility while exporting GitHub Actions signing secrets?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Release signing", "Secret-Backed Android Signing", "GitHub Actions Release Artifacts", "Cross-Platform Compatibility Contract"]
---

# Q: How does Omniverse preserve Android upgrade compatibility while exporting GitHub Actions signing secrets?

## Answer

Android update continuity requires every direct-distribution APK to remain signed by the original release identity. android/export_github_signing_secrets.py therefore reads only the ignored existing keystore.properties and keystore, validates the store password and alias with JDK keytool, requires the public certificate to match android/release-signing-cert.sha256, and exports the four GitHub Actions values to a 0600 file outside the repository without printing them. It deliberately cannot generate or rotate a key. CI reconstructs the key under umask 077, rejects any certificate that does not match the versioned continuity pin, builds the signed APK, and removes signing material with an always-run cleanup step. A replacement key would require legacy users to uninstall the existing app, so contributors must recover the original secure backup instead.

## Outcome

- Signal: useful

## Source Nodes

- Release signing
- Secret-Backed Android Signing
- GitHub Actions Release Artifacts
- Cross-Platform Compatibility Contract
