# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Autonomous watcher system — LLM-driven loops that monitor domains and fire alerts
- Built-in BEAM domain for VM metrics (memory, processes, schedulers, atoms, ports)
- `Beamlens.Domain` behaviour for implementing custom monitoring domains
- `Beamlens.list_watchers/0` — list all running watchers with status
- `Beamlens.watcher_status/1` — get details about a specific watcher
- `:client_registry` option to configure custom LLM providers (OpenAI, Ollama, AWS Bedrock, Google Gemini, etc.)
- LLM provider configuration guide with retry policies, fallback chains, and round-robin patterns
- Telemetry events for observability (watcher lifecycle, LLM calls, alerts)
- Lua sandbox for safe metric collection callbacks

### Changed

- Upgraded Puck from 0.1.0 to 0.2.2 (adds context compaction support)
- Watchers now run as continuous LLM-driven loops instead of scheduled cron jobs

### Removed

- Circuit breaker protection (use LLM provider retry policies instead)
- Judge agent quality verification
- Scheduled cron-based watcher triggers (watchers now run continuously)
- Beamlens.investigate/1 — alerts now fire automatically via telemetry
- Beamlens.trigger_watcher/1 — watchers are self-managing
- Beamlens.pending_alerts?/0 — replaced by telemetry events

## [0.1.0] - 2025-01-03

First release!

[Unreleased]: https://github.com/beamlens/beamlens/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/beamlens/beamlens/releases/tag/v0.1.0
