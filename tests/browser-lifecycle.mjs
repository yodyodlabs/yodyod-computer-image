// Real XFCE launcher regression: close Chrome, keep the desktop, reopen from
// the exact exo helper used by the panel, and verify the same durable profile.
import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { setTimeout as delay } from 'node:timers/promises';
const exec = promisify(execFile);
const endpoint = 'http://127.0.0.1:9222/json/version';
async function version() {
  return fetch(endpoint, { signal: AbortSignal.timeout(1500) }).then(r => r.ok ? r.json() : null).catch(() => null);
}
async function closeBrowser() {
  const info = await version();
  assert.ok(info, 'Chrome should be open for the close test');
  await new Promise((resolve, reject) => {
    const socket = new WebSocket(info.webSocketDebuggerUrl);
    let sent = false;
    const timer = setTimeout(() => { socket.close(); reject(new Error('Chrome close timeout')); }, 10000);
    socket.addEventListener('open', () => { sent = true; socket.send(JSON.stringify({ id: 1, method: 'Browser.close' })); });
    socket.addEventListener('close', () => { clearTimeout(timer); resolve(); });
    socket.addEventListener('error', () => { clearTimeout(timer); if (sent) resolve(); else reject(new Error('Chrome close failed')); });
  });
  for (let attempt = 0; attempt < 30 && await version(); attempt++) await delay(100);
  assert.equal(await version(), null);
  await delay(4000); // The old supervisor reopened Chrome after two seconds.
  assert.equal(await version(), null, 'Closing Chrome must not reopen it');
  await exec('/opt/yodyod/runtime/healthcheck.sh');
}
const { stdout } = await exec('xdg-mime', ['query', 'default', 'x-scheme-handler/https']);
assert.equal(stdout.trim(), 'yodyod-chrome.desktop');
await closeBrowser();
console.log('PASS closing Chrome keeps it closed and the desktop healthy');
const launch = spawn('exo-open', ['--launch', 'WebBrowser', 'about:blank'], {
  detached: true, stdio: 'ignore', env: { ...process.env, DISPLAY: ':1' },
});
launch.unref();
for (let attempt = 0; attempt < 60 && !await version(); attempt++) await delay(500);
assert.ok(await version(), 'XFCE panel helper must reopen the shared CDP browser');
console.log('PASS XFCE default WebBrowser opens shared Chrome');
await closeBrowser();
console.log('PASS closing manually reopened Chrome also keeps it closed');
