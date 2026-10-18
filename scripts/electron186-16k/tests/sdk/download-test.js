'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const root = process.env.SDK_TEST_ROOT || __dirname;
const runtime = process.env.THUNDER_RUNTIME;
const kernel = require(path.join(runtime, 'resources/bin/ThunderKernel.node'));
const helper = require(path.join(runtime, 'resources/bin/ThunderHelper.node'));
const clientCode = fs.readFileSync(path.join(runtime, 'resources/app/out/main-renderer/renderer.js'), 'utf8');
const clientKey = /["']linux_thunder["']\s*,\s*["']([^"']+)["']/.exec(clientCode);
if (!clientKey) throw new Error('Could not read the installed client SDK application identifier');
const clientVersion = require(path.join(runtime, 'resources/app/package.json')).version;
const dataDir = path.join(root, 'data');
const outputDir = path.join(root, 'downloads');
for (const dir of [dataDir, outputDir]) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir);
}
const payload = Buffer.alloc(128 * 1024);
for (let i = 0; i < payload.length; ++i) payload[i] = (i * 31 + 7) & 255;
const expected = crypto.createHash('sha256').update(payload).digest('hex');
console.log('SDK_VERSION', kernel.getDownloadSdkVersion());
let taskId;
let timer;
let finished = false;
let getRequests = 0;
let completedTask = false;
const server = http.createServer((req, res) => {
  console.log('LOCAL_HTTP', req.method, req.url, req.headers.range || '');
  if (req.method === 'GET') ++getRequests;
  let start = 0, end = payload.length - 1;
  const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
  if (range) {
    start = Number(range[1]);
    if (range[2]) end = Number(range[2]);
    res.statusCode = 206;
    res.setHeader('Content-Range', 'bytes ' + start + '-' + end + '/' + payload.length);
  }
  res.setHeader('Accept-Ranges', 'bytes');
  res.setHeader('Content-Length', end - start + 1);
  res.setHeader('Content-Type', 'application/octet-stream');
  res.end(req.method === 'HEAD' ? undefined : payload.slice(start, end + 1));
});
function finish(ok, message) {
  if (finished) return;
  finished = true;
  clearInterval(timer);
  console.log('RESULT', JSON.stringify({ok: ok, message: message, getRequests: getRequests, expectedSHA256: expected}));
  if (taskId > 0) { try { kernel.stopTask(taskId); kernel.deleteTask(taskId); } catch (_) {} }
  server.close();
  setTimeout(() => process.exit(ok ? 0 : 1), 500);
}
setTimeout(() => finish(false, 'download did not complete within 30 seconds'), 30000);
server.listen(0, '127.0.0.1', () => {
  const url = 'http://127.0.0.1:' + server.address().port + '/electron186-16k-test.bin';
  console.log('SDK_INIT_BEGIN');
  const ret = kernel.initDownloadSdk(
    'linux_thunder', clientKey[1], clientVersion,
    typeof helper.getPeerID === 'function' ? helper.getPeerID() : '00000000000000000000000000000000',
    dataDir, 'Gentoo Linux-aarch64', code => {
      console.log('SDK_INIT_CALLBACK', code);
      if (code !== 0) return finish(false, 'SDK initialization returned ' + code);
      taskId = kernel.createP2spTask(url, '', '', outputDir + '/', 'electron186-16k-test.bin');
      console.log('SDK_TASK_ID', taskId);
      if (!(taskId > 0)) return finish(false, 'createP2spTask failed: ' + taskId);
      console.log('SDK_START_RETURN', kernel.startTask(taskId));
      let count = 0;
      timer = setInterval(() => {
        kernel.queryTaskInfo(taskId, info => {
          if (count++ < 3) console.log('SDK_TASK_INFO', JSON.stringify(info));
          if (info && info.taskStatus === 7 && info.taskError === 0) completedTask = true;
        });
        const target = path.join(outputDir, 'electron186-16k-test.bin');
        if (fs.existsSync(target) && fs.statSync(target).size === payload.length) {
          const actual = crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex');
          if (actual === expected && getRequests > 0 && completedTask) finish(true, '128 KiB local HTTP download and SHA-256 verification passed');
        }
      }, 500);
    }
  );
  console.log('SDK_INIT_RETURN', ret);
});
