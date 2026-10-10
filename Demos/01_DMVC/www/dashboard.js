'use strict';

// Requests kept per lane: the columns of the chart and the window of the tiles.
const WINDOW = 40;
const LOG_ROWS = 12;
const REQUEST_TIMEOUT_MS = 10000;
const MAX_IN_FLIGHT = 8;
const CURRENCIES = ['USD', 'GBP', 'CHF', 'JPY'];
const PRODUCT_COUNT = 4;
const SVG_NS = 'http://www.w3.org/2000/svg';

const TARGETS = {
  inbound: {
    title: 'Incoming requests',
    subtitle: 'TChaosMiddleware on /api: a fault answers 503, the latency delays the answer.'
  },
  rates: {
    title: 'Exchange rates service',
    subtitle: 'Innermost in Retry → Circuit breaker → Timeout (1 s), called by the price requests.'
  }
};

const OUTCOMES = {
  ok: { label: 'Success', icon: '✓' },
  degraded: { label: 'Degraded', icon: '◐' },
  error: { label: 'Error', icon: '✕' }
};

const CIRCUIT_STATES = {
  Closed: { icon: '✓', label: 'Closed: service called' },
  HalfOpen: { icon: '◐', label: 'Half-open: trial calls' },
  Open: { icon: '✕', label: 'Open: cached rates served' },
  Isolated: { icon: '✕', label: 'Isolated: cached rates served' }
};

const lanes = [
  { id: 'normal', title: 'Normal traffic', marked: false },
  { id: 'test', title: 'Test traffic', marked: true }
];

const state = {
  markerHeader: 'X-Chaos',
  running: false,
  timers: [],
  log: [],
  settings: null,
  renderPending: false
};

const $ = (selector, root = document) => root.querySelector(selector);

// ---------------------------------------------------------------------------
// Formatting

function formatMs(ms) {
  if (ms < 1000) {
    return `${Math.round(ms)} ms`;
  }
  return `${(ms / 1000).toFixed(ms < 10000 ? 2 : 1).replace(/\.?0+$/, '')} s`;
}

function formatTime(date) {
  return date.toLocaleTimeString([], { hour12: false });
}

function percentile(values, p) {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)];
}

// ---------------------------------------------------------------------------
// Traffic

function nextRequest(lane) {
  lane.sent += 1;
  if (lane.sent % 2 === 1) {
    return { kind: 'products', url: '/api/products' };
  }
  const product = 1 + Math.floor(Math.random() * PRODUCT_COUNT);
  const currency = CURRENCIES[Math.floor(Math.random() * CURRENCIES.length)];
  return { kind: 'price', url: `/api/products/${product}/price/${currency}` };
}

async function send(lane) {
  // A slow server must not pile up requests in the browser.
  if (lane.inFlight >= MAX_IN_FLIGHT) {
    return;
  }
  lane.inFlight += 1;
  const request = nextRequest(lane);
  const record = { lane, url: request.url, kind: request.kind, status: 0, outcome: 'error', detail: '' };
  const headers = lane.marked ? { [state.markerHeader]: 'on' } : {};
  const started = performance.now();
  try {
    const signal = AbortSignal.timeout ? AbortSignal.timeout(REQUEST_TIMEOUT_MS) : undefined;
    const response = await fetch(request.url, { headers, cache: 'no-store', signal });
    const body = await response.json().catch(() => null);
    record.status = response.status;
    classify(record, response, body);
  } catch (error) {
    record.detail = error.name === 'TimeoutError'
      ? `No answer within ${REQUEST_TIMEOUT_MS / 1000} s`
      : 'Server unreachable';
  } finally {
    lane.inFlight -= 1;
  }
  record.ms = performance.now() - started;
  record.time = new Date();
  addRecord(record);
}

function classify(record, response, body) {
  const injected = response.headers.get('X-Chaos-Injected') || '';
  const latency = /^latency=(\d+)/.exec(injected);
  const notes = [];

  if (!response.ok) {
    record.outcome = 'error';
    notes.push(injected === 'fault'
      ? 'Fault injected into the request'
      : (body && body.message) || response.statusText || 'Error');
  } else if (record.kind === 'price' && body) {
    record.circuit = body.circuit;
    updateCircuit(body.circuit);
    if (body.rateSource === 'cache') {
      record.outcome = 'degraded';
      // An open circuit rejects the first attempt, which is not retried.
      notes.push(body.attempts > 1
        ? `Cached rate after ${body.attempts} attempts`
        : 'Cached rate: the circuit skipped the service');
    } else {
      record.outcome = 'ok';
      notes.push(body.attempts > 1 ? `Live rate, retried: ${body.attempts} attempts` : 'Live rate');
    }
  } else {
    record.outcome = 'ok';
    notes.push('Product list');
  }

  if (latency) {
    notes.push(`${formatMs(Number(latency[1]))} of latency injected`);
  }
  record.detail = notes.join(' · ');
}

function addRecord(record) {
  const lane = record.lane;
  lane.total += 1;
  lane.records.push(record);
  if (lane.records.length > WINDOW) {
    lane.records.shift();
  }
  state.log.unshift(record);
  if (state.log.length > LOG_ROWS) {
    state.log.pop();
  }
  scheduleRender();
}

function startTraffic() {
  stopTraffic();
  state.running = true;
  const rate = Number($('#traffic-rate').value);
  for (const lane of lanes) {
    send(lane);
    state.timers.push(setInterval(() => send(lane), 1000 / rate));
  }
  updateToolbar();
}

function stopTraffic() {
  state.timers.forEach(clearInterval);
  state.timers = [];
  state.running = false;
  updateToolbar();
}

function clearTraffic() {
  for (const lane of lanes) {
    lane.records = [];
    lane.total = 0;
  }
  state.log = [];
  scheduleRender();
}

function updateToolbar() {
  $('#traffic-toggle').textContent = state.running ? 'Stop traffic' : 'Start traffic';
}

// ---------------------------------------------------------------------------
// Rendering

function scheduleRender() {
  if (state.renderPending) {
    return;
  }
  state.renderPending = true;
  requestAnimationFrame(() => {
    state.renderPending = false;
    render();
  });
}

function render() {
  // One scale for both lanes, so that their columns compare.
  const maxMs = Math.max(1000, ...lanes.flatMap(lane => lane.records.map(r => r.ms)));
  const scale = niceScale(maxMs);
  for (const lane of lanes) {
    renderStats(lane);
    renderChart(lane, scale);
  }
  renderLog();
}

function niceScale(maxMs) {
  const steps = [250, 500, 1000, 2000, 2500, 5000, 10000];
  const step = steps.find(s => Math.ceil(maxMs / s) <= 4) || 10000;
  return { step, max: Math.ceil(maxMs / step) * step };
}

function renderStats(lane) {
  const records = lane.records;
  const count = outcome => records.filter(r => r.outcome === outcome).length;
  const p95 = percentile(records.map(r => r.ms), 0.95);
  const stat = name => $(`[data-stat="${name}"]`, lane.element);
  stat('success').textContent = records.length ? `${Math.round(100 * count('ok') / records.length)}%` : '–';
  stat('degraded').textContent = records.length ? count('degraded') : '–';
  stat('errors').textContent = records.length ? count('error') : '–';
  stat('p95').textContent = p95 === null ? '–' : formatMs(p95);
  $('.lane-total', lane.element).textContent =
    `${lane.total} ${lane.total === 1 ? 'request' : 'requests'}`;
}

function svg(name, attributes = {}) {
  const element = document.createElementNS(SVG_NS, name);
  for (const [key, value] of Object.entries(attributes)) {
    element.setAttribute(key, value);
  }
  return element;
}

function barPath(x, y, width, height, radius) {
  // Rounded at the data end, square at the baseline.
  const r = Math.min(radius, width / 2, height);
  const bottom = y + height;
  return `M${x},${bottom} V${y + r} Q${x},${y} ${x + r},${y} H${x + width - r} ` +
    `Q${x + width},${y} ${x + width},${y + r} V${bottom} Z`;
}

function renderChart(lane, scale) {
  const container = lane.chart;
  const width = Math.max(280, container.clientWidth);
  const margin = { top: 16, right: 4, bottom: 22, left: 48 };
  const plotHeight = 140;
  const height = margin.top + plotHeight + margin.bottom;
  const plotWidth = width - margin.left - margin.right;
  const baseline = margin.top + plotHeight;
  const y = ms => baseline - (ms / scale.max) * plotHeight;

  const root = svg('svg', {
    viewBox: `0 0 ${width} ${height}`,
    role: 'img',
    'aria-label': `${lane.title}: latency of the last ${lane.records.length} requests, see the table of the latest requests`
  });

  for (let tick = 0; tick <= scale.max; tick += scale.step) {
    const ty = y(tick);
    if (tick > 0) {
      root.append(svg('line', { class: 'gridline', x1: margin.left, x2: width - margin.right, y1: ty, y2: ty }));
    }
    const label = svg('text', { class: 'tick', x: margin.left - 8, y: ty + 4, 'text-anchor': 'end' });
    label.textContent = tick === 0 ? '0' : formatMs(tick);
    root.append(label);
  }

  const slotWidth = plotWidth / WINDOW;
  const barWidth = Math.min(24, Math.max(2, slotWidth - 2));
  const first = WINDOW - lane.records.length;
  lane.records.forEach((record, index) => {
    const slotX = margin.left + (first + index) * slotWidth;
    const barHeight = Math.max(2, baseline - y(record.ms));
    // The hit target is the whole slot, taller and wider than the bar.
    const slot = svg('rect', { class: 'slot', x: slotX, y: margin.top, width: slotWidth, height: plotHeight });
    slot.addEventListener('pointermove', event => showTooltip(event, record));
    slot.addEventListener('pointerleave', hideTooltip);
    root.append(slot);
    root.append(svg('path', {
      class: `bar ${record.outcome}`,
      d: barPath(slotX + (slotWidth - barWidth) / 2, baseline - barHeight, barWidth, barHeight, 4),
      'pointer-events': 'none'
    }));
    // A fast failure is a short bar: the marker keeps it visible.
    if (record.outcome !== 'ok') {
      root.append(svg('circle', {
        class: `marker ${record.outcome}`,
        cx: slotX + slotWidth / 2,
        cy: baseline - barHeight - 8,
        r: 4,
        'pointer-events': 'none'
      }));
    }
  });

  root.append(svg('line', { class: 'baseline', x1: margin.left, x2: width - margin.right, y1: baseline, y2: baseline }));
  const older = svg('text', { class: 'tick', x: margin.left, y: baseline + 16 });
  older.textContent = '← older';
  const newer = svg('text', { class: 'tick', x: width - margin.right, y: baseline + 16, 'text-anchor': 'end' });
  newer.textContent = 'newer →';
  root.append(older, newer);

  container.replaceChildren(root);
}

function outcomeElement(record) {
  const wrapper = document.createElement('span');
  wrapper.className = 'outcome';
  const swatch = document.createElement('span');
  swatch.className = `swatch outcome-${record.outcome}`;
  const text = document.createElement('span');
  const label = document.createElement('strong');
  label.textContent = `${OUTCOMES[record.outcome].icon} ${OUTCOMES[record.outcome].label}`;
  text.append(label, document.createTextNode(` · ${record.detail}`));
  wrapper.append(swatch, text);
  return wrapper;
}

function renderLog() {
  const body = $('#log-body');
  if (state.log.length === 0) {
    const row = document.createElement('tr');
    row.className = 'empty';
    const cell = document.createElement('td');
    cell.colSpan = 6;
    cell.textContent = 'Start the traffic to see the requests.';
    row.append(cell);
    body.replaceChildren(row);
    return;
  }
  const rows = state.log.map(record => {
    const row = document.createElement('tr');
    const cells = [
      [formatTime(record.time), ''],
      [record.lane.marked ? 'Test' : 'Normal', ''],
      [`GET ${record.url}`, 'request'],
      [record.status || '—', 'num'],
      [formatMs(record.ms), 'num']
    ];
    for (const [value, className] of cells) {
      const cell = document.createElement('td');
      cell.textContent = value;
      cell.className = className;
      row.append(cell);
    }
    const outcome = document.createElement('td');
    outcome.append(outcomeElement(record));
    row.append(outcome);
    return row;
  });
  body.replaceChildren(...rows);
}

// ---------------------------------------------------------------------------
// Tooltip

function showTooltip(event, record) {
  const tooltip = $('#tooltip');
  const value = document.createElement('strong');
  value.textContent = formatMs(record.ms);
  const outcome = document.createElement('div');
  outcome.textContent = `${OUTCOMES[record.outcome].icon} ${OUTCOMES[record.outcome].label}` +
    (record.status ? ` · HTTP ${record.status}` : '');
  const request = document.createElement('div');
  request.className = 'detail';
  request.textContent = `GET ${record.url}`;
  const detail = document.createElement('div');
  detail.className = 'detail';
  detail.textContent = `${record.detail} · ${formatTime(record.time)}`;
  tooltip.replaceChildren(value, outcome, request, detail);
  tooltip.hidden = false;

  const gap = 14;
  const { innerWidth, innerHeight } = window;
  const box = tooltip.getBoundingClientRect();
  let left = event.clientX + gap;
  let top = event.clientY + gap;
  if (left + box.width > innerWidth - 8) {
    left = event.clientX - gap - box.width;
  }
  if (top + box.height > innerHeight - 8) {
    top = event.clientY - gap - box.height;
  }
  tooltip.style.left = `${Math.max(8, left)}px`;
  tooltip.style.top = `${Math.max(8, top)}px`;
}

function hideTooltip() {
  $('#tooltip').hidden = true;
}

// ---------------------------------------------------------------------------
// Circuit breaker

function updateCircuit(name) {
  const info = CIRCUIT_STATES[name];
  if (!info) {
    return;
  }
  const element = $('#circuit-state');
  element.dataset.state = name;
  $('.icon', element).textContent = info.icon;
  $('#circuit-label').textContent = info.label;
}

// ---------------------------------------------------------------------------
// Chaos settings

function setStatus(message, isError = false) {
  const status = $('#settings-status');
  status.textContent = message;
  status.classList.toggle('error', isError);
}

function buildTargets(names) {
  const container = $('#targets');
  const template = $('#target-template');
  container.replaceChildren();
  for (const name of names) {
    const fragment = template.content.cloneNode(true);
    const fieldset = $('fieldset', fragment);
    fieldset.dataset.target = name;
    const info = TARGETS[name] || { title: name, subtitle: '' };
    $('.target-title', fieldset).textContent = info.title;
    $('.target-subtitle', fieldset).textContent = info.subtitle;
    for (const input of fieldset.querySelectorAll('input')) {
      const field = input.dataset.field;
      if (input.type === 'range') {
        input.addEventListener('input', () => {
          input.nextElementSibling.textContent = `${input.value}%`;
        });
        input.addEventListener('change', () =>
          putSettings({ targets: { [name]: { [field]: Number(input.value) / 100 } } }));
      } else {
        input.addEventListener('change', () =>
          putSettings({ targets: { [name]: { [field]: Math.round(Number(input.value)) } } }));
      }
    }
    container.append(fragment);
  }
}

function applySettings(settings) {
  state.settings = settings;
  state.markerHeader = settings.markerHeader || state.markerHeader;
  $('#marker-header').textContent = `${state.markerHeader}: on`;
  for (const lane of lanes) {
    $('.lane-subtitle', lane.element).textContent = lane.marked
      ? `Sends "${state.markerHeader}: on": the requests of the experiment.`
      : 'No chaos header: the requests of the real users.';
  }

  $('#chaos-enabled').checked = settings.enabled;
  for (const radio of document.querySelectorAll('input[name="blast-radius"]')) {
    radio.checked = radio.value === settings.blastRadius;
  }

  const names = Object.keys(settings.targets);
  const built = [...document.querySelectorAll('#targets fieldset')].map(f => f.dataset.target);
  if (built.join() !== names.join()) {
    buildTargets(names);
  }
  for (const name of names) {
    const fieldset = $(`#targets fieldset[data-target="${CSS.escape(name)}"]`);
    const target = settings.targets[name];
    for (const input of fieldset.querySelectorAll('input')) {
      const value = target[input.dataset.field];
      if (input.type === 'range') {
        input.value = Math.round(value * 100);
        input.nextElementSibling.textContent = `${input.value}%`;
      } else {
        input.value = value;
      }
    }
  }
}

async function loadSettings() {
  try {
    const response = await fetch('/chaos', { cache: 'no-store' });
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      throw new Error((body && body.message) || response.statusText);
    }
    applySettings(body);
    setStatus('');
  } catch (error) {
    // E.g. the dashboard is open on another machine: the settings are local only.
    const form = $('#settings');
    form.classList.add('disabled');
    for (const element of form.elements) {
      element.disabled = true;
    }
    setStatus(error.message, true);
  }
}

async function putSettings(patch) {
  setStatus('Saving…');
  try {
    const response = await fetch('/chaos', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(patch)
    });
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      throw new Error((body && body.message) || response.statusText);
    }
    applySettings(body);
    setStatus(`Saved at ${formatTime(new Date())}`);
  } catch (error) {
    // The server changed nothing: show its settings again.
    setStatus(error.message, true);
    if (state.settings) {
      applySettings(state.settings);
    }
  }
}

// ---------------------------------------------------------------------------
// Startup

function buildLanes() {
  const template = $('#lane-template');
  const container = $('#lanes');
  for (const lane of lanes) {
    const fragment = template.content.cloneNode(true);
    lane.element = $('.lane', fragment);
    lane.element.id = `lane-${lane.id}`;
    lane.element.setAttribute('aria-labelledby', `lane-${lane.id}-title`);
    const title = $('.lane-title', lane.element);
    title.id = `lane-${lane.id}-title`;
    title.textContent = lane.title;
    lane.chart = $('.chart', lane.element);
    lane.records = [];
    lane.total = 0;
    lane.sent = 0;
    lane.inFlight = 0;
    container.append(fragment);
  }
}

function init() {
  buildLanes();

  $('#traffic-toggle').addEventListener('click', () => (state.running ? stopTraffic() : startTraffic()));
  $('#traffic-rate').addEventListener('change', () => {
    if (state.running) {
      startTraffic();
    }
  });
  $('#traffic-clear').addEventListener('click', clearTraffic);
  $('#chaos-enabled').addEventListener('change', event => putSettings({ enabled: event.target.checked }));
  for (const radio of document.querySelectorAll('input[name="blast-radius"]')) {
    radio.addEventListener('change', () => putSettings({ blastRadius: radio.value }));
  }

  // Another client (e.g. curl) may have changed the settings meanwhile.
  window.addEventListener('focus', () => {
    if (!$('#settings').contains(document.activeElement)) {
      loadSettings();
    }
  });
  new ResizeObserver(scheduleRender).observe($('#lanes'));

  loadSettings();
  scheduleRender();
}

init();
