# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-27

### Added

- Home Assistant add-on structure (config.yaml, Dockerfile, run.sh)
- Express server (src/server.js) serving dashboard UI via HA ingress on port 8099
- API endpoints for calendar CRUD operations proxied through HA REST API
  - GET /api/calendars — list calendar entities
  - GET /api/calendars/:entity_id/events — get events
  - POST /api/events — create event
  - PUT /api/events/:uid — edit event
  - DELETE /api/events/:uid — delete event
- Health endpoint at GET /health (unauthenticated)
- Add-on configuration options: theme, dark_mode_start/end, weather_entity, calendar_entities
- Automatic installation of packages, themes, and background image into HA config
- Dashboard auto-registration via HA REST API
- Theme reload on startup
- Three theme variants:
  - Skylight Light — original Skylight theme (light mode)
  - Skylight Dark — dark backgrounds, light text, brighter calendar colors
  - HomeHero Playful — kid-friendly with Nunito font, rounded corners, bright colors
- Status page (public/index.html) showing server health and calendar connectivity
- repository.yaml for HA add-on repository distribution
