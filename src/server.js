/**
 * HomeHero Dashboard — Express Server
 *
 * Serves the dashboard web UI via HA ingress and proxies calendar API calls
 * to the Home Assistant REST API using the Supervisor token.
 */

const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 8099;

// ── Middleware ────────────────────────────────────────────────────────────

app.use(express.json());

// Serve static files from /public
app.use(express.static(path.join(__dirname, '..', 'public')));

// ── HA API helpers ───────────────────────────────────────────────────────

const HA_URL = process.env.SUPERVISOR_TOKEN
  ? 'http://supervisor/core/api'
  : (process.env.HA_URL || 'http://localhost:8123/api');

const HA_TOKEN = process.env.SUPERVISOR_TOKEN || process.env.HA_TOKEN || '';

/**
 * Forward a request to the Home Assistant REST API.
 */
async function haFetch(method, endpoint, body) {
  const url = `${HA_URL}${endpoint}`;
  const options = {
    method,
    headers: {
      'Authorization': `Bearer ${HA_TOKEN}`,
      'Content-Type': 'application/json',
    },
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(url, options);

  if (!response.ok) {
    const text = await response.text();
    const err = new Error(`HA API ${method} ${endpoint} returned ${response.status}: ${text}`);
    err.status = response.status;
    throw err;
  }

  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    return response.json();
  }
  return response.text();
}

// ── Auth middleware (all /api routes require Supervisor token) ────────────

function requireAuth(req, res, next) {
  if (!HA_TOKEN) {
    return res.status(503).json({
      error: 'No Supervisor token available. Is this running as an HA add-on?',
    });
  }
  next();
}

// ── Health endpoint (unauthenticated) ────────────────────────────────────

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', version: '0.1.0' });
});

// ── API Routes (authenticated via Supervisor token) ──────────────────────

const api = express.Router();
api.use(requireAuth);

// GET /api/config — return add-on options
api.get('/config', (_req, res) => {
  try {
    const optionsPath = process.env.HOMEHERO_OPTIONS_FILE || '/data/options.json';
    if (fs.existsSync(optionsPath)) {
      const options = JSON.parse(fs.readFileSync(optionsPath, 'utf8'));
      return res.json(options);
    }
    return res.json({});
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// GET /api/calendars — list all calendar entities from HA
api.get('/calendars', async (_req, res) => {
  try {
    const calendars = await haFetch('GET', '/calendars');
    res.json(calendars);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

// GET /api/calendars/:entity_id/events — get events for a calendar
api.get('/calendars/:entity_id/events', async (req, res) => {
  try {
    const { entity_id } = req.params;
    const { start, end } = req.query;

    let endpoint = `/calendars/${encodeURIComponent(entity_id)}`;
    const params = new URLSearchParams();
    if (start) params.append('start', start);
    if (end) params.append('end', end);
    if (params.toString()) endpoint += `?${params.toString()}`;

    const events = await haFetch('GET', endpoint);
    res.json(events);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

// POST /api/events — create a calendar event via HA service call
api.post('/events', async (req, res) => {
  try {
    const { entity_id, summary, description, start_date_time, end_date_time, start_date, end_date } = req.body;

    if (!entity_id || !summary) {
      return res.status(400).json({ error: 'entity_id and summary are required' });
    }

    const serviceData = { summary };
    if (description) serviceData.description = description;

    // All-day event vs timed event
    if (start_date && end_date) {
      serviceData.start_date = start_date;
      serviceData.end_date = end_date;
    } else if (start_date_time && end_date_time) {
      serviceData.start_date_time = start_date_time;
      serviceData.end_date_time = end_date_time;
    } else {
      return res.status(400).json({
        error: 'Provide either start_date/end_date (all-day) or start_date_time/end_date_time (timed)',
      });
    }

    await haFetch('POST', '/services/calendar/create_event', {
      entity_id,
      ...serviceData,
    });

    res.json({ success: true });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

// PUT /api/events/:uid — edit a calendar event
api.put('/events/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    const { entity_id, summary, description, start_date_time, end_date_time, start_date, end_date } = req.body;

    if (!entity_id) {
      return res.status(400).json({ error: 'entity_id is required' });
    }

    const serviceData = { uid };
    if (summary) serviceData.summary = summary;
    if (description !== undefined) serviceData.description = description;

    if (start_date && end_date) {
      serviceData.start_date = start_date;
      serviceData.end_date = end_date;
    } else if (start_date_time && end_date_time) {
      serviceData.start_date_time = start_date_time;
      serviceData.end_date_time = end_date_time;
    }

    await haFetch('POST', '/services/calendar/update_event', {
      entity_id,
      ...serviceData,
    });

    res.json({ success: true });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

// DELETE /api/events/:uid — delete a calendar event
api.delete('/events/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    const { entity_id } = req.body;

    if (!entity_id) {
      return res.status(400).json({ error: 'entity_id is required' });
    }

    await haFetch('POST', '/services/calendar/delete_event', {
      entity_id,
      uid,
    });

    res.json({ success: true });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

app.use('/api', api);

// ── Fallback: serve index.html for SPA-style routing ─────────────────────

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

// ── Start server ─────────────────────────────────────────────────────────

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[HomeHero] Server listening on http://0.0.0.0:${PORT}`);
  console.log(`[HomeHero] HA API: ${HA_URL}`);
  console.log(`[HomeHero] Supervisor token: ${HA_TOKEN ? 'present' : 'NOT SET'}`);
});
