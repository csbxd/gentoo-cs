import fs from 'node:fs';
import path from 'node:path';
import {setTimeout as sleep} from 'node:timers/promises';

const [portText, outputDirectory, durationText = '90000'] = process.argv.slice(2);
const port = Number(portText);
const duration = Number(durationText);
if (!Number.isInteger(port) || port < 1 || port > 65535 || !outputDirectory || !(duration > 0)) {
  throw new Error('Usage: node cdp-observe.mjs LOCAL_PORT OUTPUT_DIRECTORY [DURATION_MS]');
}
fs.mkdirSync(outputDirectory, {recursive: true});
const started = Date.now();
const eventsFile = path.join(outputDirectory, 'cdp-events.jsonl');
const snapshotsFile = path.join(outputDirectory, 'cdp-snapshots.jsonl');
fs.writeFileSync(eventsFile, '');
fs.writeFileSync(snapshotsFile, '');
const targets = new Map();
let stopping = false;
let endpointAvailable = null;
let discoveryFailures = 0;
let discoveryCount = 0;
const endpoint = `http://127.0.0.1:${port}/json`;
const cut = (value, max = 10000) => String(value ?? '').slice(0, max);
const record = (kind, data = {}) => fs.appendFileSync(eventsFile, JSON.stringify({
  elapsedMs: Date.now() - started, timestamp: new Date().toISOString(), kind, ...data
}) + '\n');

function classify(snapshot) {
  if (!snapshot.documentAvailable) return 'no_document';
  const text = snapshot.bodyText || '';
  const mainIndicators = ['正在下载', '已完成', '回收站', '新建'].filter(word => text.includes(word));
  const loginIndicators = ['登录', '登陆', '二维码', '验证码', '密码', 'login', 'sign in'].filter(word => text.toLowerCase().includes(word));
  return {mainIndicators, loginIndicators,
    guess: mainIndicators.length >= 2 ? 'main_interface' : loginIndicators.length >= 2 ? 'login_page' : text.trim() ? 'other_page_with_text' : 'page_without_text'};
}

const snapshotExpression = `(() => {
  if (typeof document === 'undefined') return {documentAvailable:false};
  const body = document.body;
  const count = (selector) => document.querySelectorAll(selector).length;
  return {
    documentAvailable:true, title:document.title, url:document.URL,
    readyState:document.readyState, visibility:document.visibilityState,
    bodyText:body ? body.innerText.slice(0,16000) : '',
    bodyChildren:body ? body.children.length : 0,
    elementCount:count('body *'), imageCount:count('img'), canvasCount:count('canvas'),
    iframeCount:count('iframe'), inputCount:count('input'), buttonCount:count('button'),
    viewport:typeof window === 'undefined' ? null : {width:window.innerWidth,height:window.innerHeight},
    bodyRect:body ? {width:body.getBoundingClientRect().width,height:body.getBoundingClientRect().height} : null
  };
})()`;

function connect(target) {
  const state = targets.get(target.id) || {
    id: target.id, firstSeenMs: Date.now() - started, connections: 0,
    protocolErrors: [], javascriptExceptions: [], consoleErrors: [], crashEvents: [],
    snapshots: 0, lastSnapshot: null, lastSnapshotJson: '', lastSnapshotAt: 0
  };
  state.target = target;
  state.lastSeenMs = Date.now() - started;
  state.present = true;
  state.connections++;
  state.closed = false;
  state.nextId = 0;
  state.pending = new Map();
  state.connectingAt = Date.now();
  targets.set(target.id, state);
  let ws;
  try { ws = new WebSocket(target.webSocketDebuggerUrl); }
  catch (error) {
    state.closed = true;
    state.retryAfter = Date.now() + 1000;
    record('target_connect_error', {targetId: target.id, error: cut(error.message)});
    return;
  }
  state.ws = ws;

  state.send = (method, params = {}) => new Promise((resolve, reject) => {
    if (state.closed || ws.readyState !== WebSocket.OPEN) return reject(new Error('target socket is not open'));
    const id = ++state.nextId;
    const timeout = setTimeout(() => { state.pending.delete(id); reject(new Error(`${method} timed out`)); }, 2500);
    state.pending.set(id, {resolve, reject, timeout, method});
    ws.send(JSON.stringify({id, method, params}));
  });

  state.snapshot = async () => {
    if (state.closed || state.snapshotPending || ws.readyState !== WebSocket.OPEN) return;
    state.snapshotPending = true;
    state.lastSnapshotAt = Date.now();
    try {
      const result = await state.send('Runtime.evaluate', {expression: snapshotExpression, returnByValue: true});
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text || 'snapshot evaluation failed');
      const value = result.result?.value;
      if (!value || typeof value !== 'object') throw new Error('snapshot returned no value');
      value.classification = classify(value);
      const json = JSON.stringify(value);
      state.lastSnapshot = value;
      state.lastSnapshotError = null;
      state.snapshots++;
      if (json !== state.lastSnapshotJson) {
        fs.appendFileSync(snapshotsFile, JSON.stringify({elapsedMs: Date.now() - started, targetId: target.id, ...value}) + '\n');
        state.lastSnapshotJson = json;
        record('page_snapshot_changed', {targetId: target.id, title: value.title, url: value.url, classification: value.classification});
      }
    } catch (error) {
      const message = cut(error.message);
      if (message !== state.lastSnapshotError) record('page_snapshot_error', {targetId: target.id, error: message});
      state.lastSnapshotError = message;
    } finally { state.snapshotPending = false; }
  };

  ws.addEventListener('open', async () => {
    record('target_connected', {targetId: target.id, type: target.type, title: target.title, url: target.url});
    for (const domain of ['Runtime', 'Page', 'Console', 'Inspector']) {
      try { await state.send(`${domain}.enable`); }
      catch (error) { state.protocolErrors.push({method: `${domain}.enable`, error: cut(error.message)}); }
    }
    await state.snapshot();
  });

  ws.addEventListener('message', event => {
    let message;
    try { message = JSON.parse(event.data); }
    catch (error) { record('protocol_decode_error', {targetId: target.id, error: cut(error.message)}); return; }
    if (message.id) {
      const pending = state.pending.get(message.id);
      if (!pending) return;
      state.pending.delete(message.id);
      clearTimeout(pending.timeout);
      if (message.error) pending.reject(new Error(`${pending.method}: ${message.error.message}`));
      else pending.resolve(message.result || {});
      return;
    }
    const {method, params = {}} = message;
    if (method === 'Runtime.exceptionThrown') {
      const detail = params.exceptionDetails || {};
      const item = {message: cut(detail.exception?.description || detail.text), url: detail.url,
        lineNumber: detail.lineNumber, columnNumber: detail.columnNumber, stackTrace: detail.stackTrace};
      state.javascriptExceptions.push(item);
      record('javascript_exception', {targetId: target.id, ...item});
    } else if (method === 'Runtime.consoleAPICalled') {
      const item = {type: params.type, text: cut((params.args || []).map(argument => argument.value ?? argument.description ?? argument.type).join(' ')), stackTrace: params.stackTrace};
      if (['error', 'assert'].includes(params.type)) state.consoleErrors.push(item);
      record('javascript_console', {targetId: target.id, ...item});
    } else if (method === 'Console.messageAdded') {
      const item = params.message || {};
      if (item.level === 'error') state.consoleErrors.push(item);
      record('console_message', {targetId: target.id, message: item});
    } else if (method?.startsWith('Page.') && ['Page.frameStartedLoading', 'Page.frameStoppedLoading', 'Page.frameNavigated', 'Page.loadEventFired', 'Page.domContentEventFired'].includes(method)) {
      record('page_event', {targetId: target.id, method, params});
      if (Date.now() - state.lastSnapshotAt > 500) void state.snapshot();
    } else if (['Inspector.targetCrashed', 'Target.targetCrashed', 'Inspector.detached'].includes(method)) {
      state.crashEvents.push({method, params});
      record('target_crash_or_detach', {targetId: target.id, method, params});
    }
  });
  const close = (kind, detail) => {
    state.closed = true;
    state.retryAfter = Date.now() + 1000;
    for (const pending of state.pending.values()) { clearTimeout(pending.timeout); pending.reject(new Error('target connection closed')); }
    state.pending.clear();
    record(kind, {targetId: target.id, ...detail});
  };
  ws.addEventListener('close', event => close('target_socket_closed', {code: event.code, reason: event.reason}));
  ws.addEventListener('error', event => record('target_socket_error', {targetId: target.id, error: cut(event.message || 'WebSocket error')}));
}

process.on('SIGTERM', () => { stopping = true; });
process.on('SIGINT', () => { stopping = true; });
record('observer_started', {endpoint, durationMs: duration});
while (!stopping && Date.now() - started < duration) {
  try {
    const response = await fetch(endpoint, {signal: AbortSignal.timeout(1200)});
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const discovered = await response.json();
    if (!Array.isArray(discovered)) throw new Error('/json did not return an array');
    discoveryCount++;
    if (endpointAvailable !== true) record('endpoint_available');
    endpointAvailable = true;
    const present = new Set();
    for (const target of discovered) {
      if (!target.id || !target.webSocketDebuggerUrl || String(target.url).startsWith('devtools://')) continue;
      // The browser is always reached through the loopback endpoint. Do not follow remote WS URLs.
      const websocketUrl = new URL(target.webSocketDebuggerUrl);
      if (!['127.0.0.1', 'localhost', '[::1]'].includes(websocketUrl.hostname)) {
        record('non_loopback_target_skipped', {targetId: target.id}); continue;
      }
      present.add(target.id);
      const state = targets.get(target.id);
      if (!state || (state.closed && Date.now() >= state.retryAfter)) connect(target);
      else {
        state.target = target; state.present = true; state.lastSeenMs = Date.now() - started;
        if (Date.now() - state.lastSnapshotAt > 3000) void state.snapshot?.();
      }
    }
    for (const state of targets.values()) {
      if (state.present && !present.has(state.id)) {
        state.present = false;
        record('target_disappeared', {targetId: state.id, url: state.target?.url});
      }
    }
  } catch (error) {
    discoveryFailures++;
    if (endpointAvailable !== false) record('endpoint_unavailable', {error: cut(error.message)});
    endpointAvailable = false;
  }
  await sleep(400);
}
for (const state of targets.values()) { try { state.ws?.close(); } catch {} }
const pages = [...targets.values()].map(state => ({
  id: state.id, target: state.target, present: state.present,
  firstSeenMs: state.firstSeenMs, lastSeenMs: state.lastSeenMs, connections: state.connections,
  snapshots: state.snapshots, lastSnapshot: state.lastSnapshot,
  javascriptExceptions: state.javascriptExceptions, consoleErrors: state.consoleErrors,
  crashEvents: state.crashEvents, protocolErrors: state.protocolErrors,
  lastSnapshotError: state.lastSnapshotError
}));
const summary = {endpoint, durationMs: Date.now() - started, discoveryCount, discoveryFailures,
  pageCount: pages.length, javascriptExceptionCount: pages.reduce((n, p) => n + p.javascriptExceptions.length, 0),
  crashOrDetachEventCount: pages.reduce((n, p) => n + p.crashEvents.length, 0), pages};
fs.writeFileSync(path.join(outputDirectory, 'cdp-pages.json'), JSON.stringify(summary, null, 2));
record('observer_finished', {pageCount: pages.length, javascriptExceptionCount: summary.javascriptExceptionCount});
console.log(JSON.stringify({pageCount: pages.length, javascriptExceptionCount: summary.javascriptExceptionCount, summaryFile: path.join(outputDirectory, 'cdp-pages.json')}));
setTimeout(() => process.exit(0), 200).unref();
