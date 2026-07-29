---
type: "explain"
date: "2026-07-29T05:45:30.936234+00:00"
question: "Why did the GitHub Actions macOS DMG job fail while signing the Intel Electron bundle?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["sortCodeTargetsInsideOut()", "collectCodeTargets()", "signAppInsideOut()", "afterPack.test.js", "Release Verification Gate"]
---

# Q: Why did the GitHub Actions macOS DMG job fail while signing the Intel Electron bundle?

## Answer

Expanded from graph vocabulary: [electron, mac, codesign, framework, helper, dmg, verification]. The afterPack hook discovered nested code recursively but signed targets in filesystem enumeration order. On the x64 Electron archive, the enclosing Electron Framework binary was processed before chrome_crashpad_handler, so codesign rejected the unsigned nested component. The fix sorts unique code targets deepest-first, always seals Omniverse.app last, adds an ordering regression test, disables implicit electron-builder publishing for the macOS packaging step, and verifies both application signatures, architectures, and DMG checksums in CI.

## Outcome

- Signal: useful

## Source Nodes

- sortCodeTargetsInsideOut()
- collectCodeTargets()
- signAppInsideOut()
- afterPack.test.js
- Release Verification Gate