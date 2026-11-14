import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { fileURLToPath } from 'node:url';

test('desktop server exposes its tools and rejects unsafe input over real MCP', async () => {
  const client = new Client({ name: 'desktop-contract-test', version: '1.0.0' });
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [fileURLToPath(new URL('../tools/desktop-mcp.mjs', import.meta.url))],
    stderr: 'pipe',
  });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    assert.equal(tools.length, 8);
    assert.equal(tools.find(t => t.name === 'desktop_screenshot').annotations.readOnlyHint, true);
    const invalid = await client.callTool({ name: 'desktop_key', arguments: { key: '--clearmodifiers;echo bad' } });
    assert.equal(invalid.isError, true);
    const negative = await client.callTool({ name: 'desktop_click', arguments: { x: -1, y: 0 } });
    assert.equal(negative.isError, true);
  } finally { await client.close(); }
});
