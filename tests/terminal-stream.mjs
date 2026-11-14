// Exercise the same ttyd protocol as the application's xterm client.
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';

const socket = new WebSocket('ws://127.0.0.1:7681/ws', ['tty']);
socket.binaryType = 'arraybuffer';
const encoder = new TextEncoder();
const decoder = new TextDecoder();
let output = '', shellPid;
const send = data => socket.send(encoder.encode(data));
socket.addEventListener('message', event => {
  const frame = new Uint8Array(event.data);
  if (frame[0] === 48) output += decoder.decode(frame.subarray(1), { stream: true });
});
async function waitFor(predicate, message) {
  for (let i = 0; i < 200; i++) {
    if (predicate()) return;
    await delay(25);
  }
  assert.fail(message);
}
try {
  await waitFor(() => socket.readyState === WebSocket.OPEN, 'terminal socket opens');
  send(JSON.stringify({ AuthToken: '', columns: 83, rows: 31 }));
  send("0printf 'terminal-%s\\n' ready; printf 'shell-%s\\n' $$; stty size\r");
  await waitFor(() => /terminal-ready\r?\n/.test(output) && /31 83/.test(output), 'shell output and initial dimensions');
  shellPid = Number(output.match(/shell-(\d+)/)?.[1]);
  assert.ok(shellPid, 'a real shell has a PID');
  send('1' + JSON.stringify({ columns: 97, rows: 35 }));
  send("0stty size; printf '\\u4e2d\\u6587-%s\\n' success\r");
  await waitFor(() => /35 97/.test(output) && /中文-success/.test(output), 'resize and UTF-8 output');
  const start = output.length;
  send("0printf '中文输入-%s\\n' 正常\r");
  await waitFor(() => output.slice(start).includes('中文输入-正常'), 'UTF-8 keyboard input');
  send("0printf 'interrupt-%s\\n' ready; sleep 30\r");
  await waitFor(() => /interrupt-ready/.test(output), 'blocking command started');
  send('0\x03');
  send("0printf 'interrupt-%s\\n' success\r");
  await waitFor(() => /interrupt-success/.test(output), 'Ctrl+C interrupts without waiting for the command');
  send("0python3 -c \"print('x'*300000); print('bulk-'+'success')\"\r");
  await waitFor(() => output.includes('bulk-success'), 'large output streams completely');
  assert.ok(output.includes('x'.repeat(100000)), 'bulk output is not truncated');
  console.log('PASS direct terminal input, Unicode, resize, Ctrl+C and bulk output');
} finally {
  socket.close();
}
if (shellPid) {
  await waitFor(() => {
    try { process.kill(shellPid, 0); return false; }
    catch (error) { if (error.code === 'ESRCH') return true; throw error; }
  }, 'disconnect releases the shell');
  console.log('PASS terminal disconnect releases its shell');
}
