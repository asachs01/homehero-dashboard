#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# HomeHero Dashboard — Add-on Startup Script
# ---------------------------------------------------------------------------
# Reads options from /data/options.json, copies HA config files into place,
# registers the dashboard via the HA REST API, and starts the Node server.
# ---------------------------------------------------------------------------

echo "[HomeHero] Starting HomeHero Dashboard add-on v0.1.0"

# ── 1. Read add-on options ─────────────────────────────────────────────────
OPTIONS_FILE="/data/options.json"
if [ ! -f "$OPTIONS_FILE" ]; then
  echo "[HomeHero] WARNING: No options.json found, using defaults."
  OPTIONS_FILE="/app/defaults.json"
fi

THEME=$(jq -r '.theme // "auto"' "$OPTIONS_FILE")
DARK_START=$(jq -r '.dark_mode_start // "20:00"' "$OPTIONS_FILE")
DARK_END=$(jq -r '.dark_mode_end // "07:00"' "$OPTIONS_FILE")
WEATHER_ENTITY=$(jq -r '.weather_entity // "weather.home"' "$OPTIONS_FILE")

echo "[HomeHero] Theme: ${THEME} | Dark mode: ${DARK_START}-${DARK_END}"
echo "[HomeHero] Weather entity: ${WEATHER_ENTITY}"

# ── 2. Copy packages to HA config dir ─────────────────────────────────────
HA_CONFIG="/config"
PACKAGES_DIR="${HA_CONFIG}/packages"
THEMES_DIR="${HA_CONFIG}/themes"
WWW_DIR="${HA_CONFIG}/www"

echo "[HomeHero] Installing HA package files..."

mkdir -p "$PACKAGES_DIR"
cp /app/packages/family_calendar.yaml "$PACKAGES_DIR/family_calendar.yaml"
echo "[HomeHero]   -> packages/family_calendar.yaml installed"

mkdir -p "$THEMES_DIR"
# Copy all theme files
for theme_file in /app/themes/*.yaml; do
  if [ -f "$theme_file" ]; then
    cp "$theme_file" "$THEMES_DIR/$(basename "$theme_file")"
    echo "[HomeHero]   -> themes/$(basename "$theme_file") installed"
  fi
done

mkdir -p "$WWW_DIR"
if [ -f /app/calbackgrd.png ]; then
  cp /app/calbackgrd.png "$WWW_DIR/calbackgrd.png"
  echo "[HomeHero]   -> www/calbackgrd.png installed"
fi

# ── 3. Ensure packages include_dir is configured ──────────────────────────
# Check if configuration.yaml has packages directive
if [ -f "${HA_CONFIG}/configuration.yaml" ]; then
  if ! grep -q "packages:" "${HA_CONFIG}/configuration.yaml"; then
    echo "[HomeHero] WARNING: packages/ directive not found in configuration.yaml"
    echo "[HomeHero] You may need to add this to your configuration.yaml:"
    echo "[HomeHero]   homeassistant:"
    echo "[HomeHero]     packages: !include_dir_named packages"
  fi
fi

# ── 4. Register dashboard via HA REST API ─────────────────────────────────
HA_API="http://supervisor/core/api"

register_dashboard() {
  echo "[HomeHero] Registering dashboard with Home Assistant..."

  # Read the dashboard YAML content
  DASHBOARD_YAML=$(cat /app/dashboard.yaml)

  # Check if the dashboard already exists
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    "${HA_API}/lovelace/dashboards")

  if [ "$HTTP_CODE" = "200" ]; then
    # List existing dashboards to check if ours exists
    DASHBOARDS=$(curl -s \
      -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
      -H "Content-Type: application/json" \
      "${HA_API}/lovelace/dashboards")

    EXISTING=$(echo "$DASHBOARDS" | jq -r '.[] | select(.url_path == "family-calendar") | .url_path' 2>/dev/null || echo "")

    if [ -z "$EXISTING" ]; then
      echo "[HomeHero] Creating 'family-calendar' dashboard..."
      curl -s -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
          "mode": "yaml",
          "title": "Family Calendar",
          "icon": "mdi:calendar-heart",
          "url_path": "family-calendar",
          "require_admin": false,
          "show_in_sidebar": true
        }' \
        "${HA_API}/lovelace/dashboards" || echo "[HomeHero] WARNING: Could not create dashboard"
    else
      echo "[HomeHero] Dashboard 'family-calendar' already exists, skipping creation."
    fi
  else
    echo "[HomeHero] WARNING: Could not reach HA API (HTTP ${HTTP_CODE}). Dashboard not registered."
    echo "[HomeHero] The dashboard YAML is available at ${HA_CONFIG}/packages/ for manual setup."
  fi

  # Reload themes so HA picks up the new theme files
  echo "[HomeHero] Reloading themes..."
  curl -s -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    "${HA_API}/services/frontend/reload_themes" || echo "[HomeHero] WARNING: Could not reload themes"
}

# Run dashboard registration in background so server starts quickly
register_dashboard &

# ── 5. Export config for the Node.js server ───────────────────────────────
export HOMEHERO_THEME="$THEME"
export HOMEHERO_DARK_START="$DARK_START"
export HOMEHERO_DARK_END="$DARK_END"
export HOMEHERO_WEATHER_ENTITY="$WEATHER_ENTITY"
export HOMEHERO_OPTIONS_FILE="$OPTIONS_FILE"

# ── 6. Start the Node.js server ──────────────────────────────────────────
echo "[HomeHero] Starting web server on port 8099..."
cd /app
exec node src/server.js
