#!/usr/bin/env node
// Real protocol/browser/desktop checks. No model credentials or paid calls.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const clients = [];
async function connect(command, args, env = {}) {
  const client = new Client({ name: 'yodyod-image-smoke', version: '0.1.0' });
  const transport = new StdioClientTransport({ command, args, env: { ...process.env, ...env }, stderr: 'inherit' });
  await client.connect(transport);
  clients.push(client);
  return client;
}
async function call(client, name, args = {}) {
  const result = await client.callTool({ name, arguments: args }, undefined, { timeout: 90_000 });
  assert.ok(!result.isError, `${name}: ${JSON.stringify(result.content)}`);
  return result;
}
const contents = (result) => result.content.filter(c => c.type === 'text').map(c => c.text).join('\n');

async function checkAppServer() {
  const child = spawn(process.env.CODEX_BIN, ['app-server'], { stdio: ['pipe', 'pipe', 'inherit'] });
  const lines = createInterface({ input: child.stdout });
  try {
    const response = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Codex initialize timed out')), 30_000);
      lines.on('line', line => {
        try {
          const message = JSON.parse(line);
          if (message.id === 1) { clearTimeout(timer); resolve(message); }
        } catch { /* Ignore non-protocol logging. */ }
      });
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('exit', code => { clearTimeout(timer); reject(new Error(`Codex exited ${code}`)); });
    });
    child.stdin.write(JSON.stringify({ id: 1, method: 'initialize', params: {
      clientInfo: { name: 'yodyod_image_smoke', version: '0.1.0' }, capabilities: {},
    } }) + '\n');
    const message = await response;
    assert.ok(message.result, JSON.stringify(message));
    child.stdin.write(JSON.stringify({ method: 'initialized' }) + '\n');
    console.log('PASS Codex app-server initialize');
  } finally {
    lines.close();
    child.stdin.end();
    child.kill('SIGTERM');
    if (child.exitCode === null) await once(child, 'exit');
  }
}

const fixture = createServer((_req, response) => {
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  response.end('<!doctype html><html><head><title>YodYod smoke fixture</title></head>' +
    '<body><h1>YodYod browser and desktop integration</h1>' +
    '<label>Unicode test <input id="unicode"></label></body></html>');
});
await new Promise(resolve => fixture.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${fixture.address().port}`;

try {
  await checkAppServer();
  const browser = await connect('/usr/local/bin/node', [
    '/opt/yodyod/tools/node_modules/@playwright/mcp/cli.js',
    '--cdp-endpoint', 'http://127.0.0.1:9222', '--caps', 'vision',
  ]);
  const navigation = await call(browser, 'browser_navigate', { url });
  assert.match(contents(navigation), /YodYod smoke fixture/);
  // Recent Playwright MCP versions return a snapshot file reference, so verify
  // the actual DOM rather than depending on the navigation response format.
  const body = await call(browser, 'browser_evaluate', { function: '() => document.body.innerText' });
  assert.match(contents(body), /YodYod browser and desktop integration/);
  if (process.argv.includes('--after-restart')) {
    const cookie = await call(browser, 'browser_evaluate', { function: '() => document.cookie' });
    assert.match(contents(cookie), /yodyod_smoke=1/);
    console.log('PASS Chrome profile survives restart');
  }
  await call(browser, 'browser_evaluate', {
    function: '() => { document.cookie = "yodyod_smoke=1; Max-Age=3600; Path=/"; document.querySelector("#unicode").focus(); }',
  });
  console.log('PASS Playwright MCP drives visible Chrome');

  const desktop = await connect('/usr/local/bin/node', ['/opt/yodyod/tools/tools/desktop-mcp.mjs']);
  const shot = await call(desktop, 'desktop_screenshot');
  const png = shot.content.find(c => c.type === 'image');
  assert.ok(png);
  assert.equal(Buffer.from(png.data, 'base64').subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  await call(desktop, 'desktop_move', { x: 20, y: 20 });
  await call(desktop, 'desktop_key', { key: 'ctrl+a' });
  await call(desktop, 'desktop_type', { text: '你好 YodYod ✓' });
  const value = await call(browser, 'browser_evaluate', { function: '() => document.querySelector("#unicode").value' });
  assert.match(contents(value), /你好 YodYod ✓/);
  console.log('PASS desktop screenshot, mouse, keyboard and Unicode paste');

  const browserUse = await connect('/opt/yodyod/browser-use/.venv/bin/browser-use', ['--cli-mcp'], {
    BU_NAME: 'yodyod-smoke', BU_CDP_URL: 'http://127.0.0.1:9222',
  });
  const tools = await browserUse.listTools();
  assert.ok(tools.tools.some(tool => tool.name === 'browser_exec'));
  const info = await call(browserUse, 'browser_exec', {
    code: `new_tab(${JSON.stringify(url)})\nprint(page_info())`,
  });
  assert.match(contents(info), /YodYod/);
  console.log('PASS Browser Use MCP attaches to shared Chrome without a cloud API key');
} finally {
  for (const client of clients.reverse()) await client.close();
  await new Promise(resolve => fixture.close(resolve));
}
