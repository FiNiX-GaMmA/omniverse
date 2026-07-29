---
type: "explain"
date: "2026-07-29T05:24:09.204317+00:00"
question: "Which Omniverse surfaces and update paths must remain compatible during the mobile redesign, AdShield telemetry fix, security hardening, and release validation?"
contributor: "graphify"
outcome: "useful"
---

# Q: Which Omniverse surfaces and update paths must remain compatible during the mobile redesign, AdShield telemetry fix, security hardening, and release validation?

## Answer

The shared product surface spans native Android and iOS shells plus the Electron desktop client. Regression gates must cover navigation, sync payloads, updater URL/version handling, media URL schemes, AdShield main-to-preload-to-renderer telemetry, platform release builds, and signed Apple Silicon packaging. These relationships informed the README architecture chart and the 48-test cross-platform matrix.

## Outcome

- Signal: useful