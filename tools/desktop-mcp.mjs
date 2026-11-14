#!/usr/bin/env node
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

const exec = promisify(execFile);
const run = (command, args) => exec(command, args, {
  env: { ...process.env, DISPLAY: process.env.DISPLAY || ':1' },
  timeout: 15_000, maxBuffer: 1024 * 1024,
});
const text = (value) => ({ content: [{ type: 'text', text: JSON.stringify(value) }] });
const coordinate = z.number().int().min(0).max(32767);
const point = { x: coordinate, y: coordinate };

export async function screenSize() {
  const { stdout } = await run('xdotool', ['getdisplaygeometry']);
  const [width, height] = stdout.trim().split(/\s+/).map(Number);
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1) {
    throw new Error('Cannot determine the X desktop dimensions.');
  }
  return { width, height };
}

async function checkPoint(x, y) {
  const { width, height } = await screenSize();
  if (x >= width || y >= height) throw new Error(`Point is outside the ${width}x${height} screen.`);
}

export function createServer() {
  const server = new McpServer({ name: 'yodyod-desktop', version: '0.1.0' }, {
    instructions: 'Control the user-visible XFCE desktop on DISPLAY=:1. Take a screenshot before acting; use its pixel coordinates. The user shares this mouse and keyboard. Stop while the user takes over. Prefer the browser MCP for web page elements.',
  });
  const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
  const interaction = { readOnlyHint: false, destructiveHint: true, openWorldHint: true };
  const register = (name, description, inputSchema, callback, annotations = interaction) => {
    server.registerTool(name, { description, inputSchema, annotations }, async (args) => {
      try { return await callback(args); }
      catch (error) { return { isError: true, content: [{ type: 'text', text: error.message }] }; }
    });
  };
  register('desktop_get_screen_size', 'Get current desktop dimensions in screenshot pixels.', {},
    async () => text(await screenSize()), readOnly);
  register('desktop_screenshot', 'Capture the entire visible desktop. Coordinates use the original image pixels.', {}, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'yodyod-screen-'));
    try {
      const file = join(directory, 'screen.png');
      await run('scrot', ['--overwrite', file]);
      const data = await readFile(file);
      return { content: [
        { type: 'text', text: JSON.stringify(await screenSize()) },
        { type: 'image', data: data.toString('base64'), mimeType: 'image/png' },
      ] };
    } finally { await rm(directory, { recursive: true, force: true }); }
  }, readOnly);
  register('desktop_move', 'Move the mouse to a screen position.', point, async ({ x, y }) => {
    await checkPoint(x, y);
    await run('xdotool', ['mousemove', '--sync', String(x), String(y)]);
    return text({ x, y });
  });
  register('desktop_click', 'Click a screen position with the selected button.', {
    ...point, button: z.enum(['left', 'middle', 'right']).default('left'),
    clicks: z.number().int().min(1).max(3).default(1),
  }, async ({ x, y, button, clicks }) => {
    await checkPoint(x, y);
    await run('xdotool', ['mousemove', '--sync', String(x), String(y), 'click',
      '--repeat', String(clicks), '--delay', '100', String({ left: 1, middle: 2, right: 3 }[button])]);
    return text({ x, y, button, clicks });
  });
  register('desktop_drag', 'Drag with the left button between two screen positions.', {
    from_x: coordinate, from_y: coordinate, to_x: coordinate, to_y: coordinate,
  }, async ({ from_x, from_y, to_x, to_y }) => {
    await checkPoint(from_x, from_y);
    await checkPoint(to_x, to_y);
    try {
      await run('xdotool', ['mousemove', '--sync', String(from_x), String(from_y), 'mousedown', '1',
        'mousemove', '--sync', String(to_x), String(to_y)]);
    } finally { await run('xdotool', ['mouseup', '1']); }
    return text({ dragged: true });
  });
  register('desktop_key', 'Press an X11 key or chord, e.g. Return, ctrl+l, alt+Tab, ctrl+shift+t.', {
    key: z.string().min(1).max(128).regex(/^[A-Za-z0-9_+]+$/),
  }, async ({ key }) => {
    await run('xdotool', ['key', '--clearmodifiers', key]);
    return text({ pressed: key });
  });
  register('desktop_type', 'Paste Unicode text into the focused application using the clipboard.', {
    text: z.string().max(100_000),
  }, async ({ text: value }) => {
    // Do not capture xclip's pipes: its background selection owner inherits them.
    await new Promise((resolve, reject) => {
      const child = spawn('xclip', ['-selection', 'clipboard', '-in'], {
        stdio: ['pipe', 'ignore', 'ignore'],
        env: { ...process.env, DISPLAY: process.env.DISPLAY || ':1' },
      });
      child.once('error', reject);
      child.once('exit', (code) => code === 0 ? resolve() : reject(new Error(`xclip exited ${code}`)));
      child.stdin.on('error', reject);
      child.stdin.end(value);
    });
    await run('xdotool', ['key', '--clearmodifiers', 'ctrl+v']);
    return text({ pastedCharacters: [...value].length });
  });
  register('desktop_scroll', 'Scroll at the current mouse position.', {
    direction: z.enum(['up', 'down', 'left', 'right']),
    amount: z.number().int().min(1).max(50).default(3),
  }, async ({ direction, amount }) => {
    await run('xdotool', ['click', '--repeat', String(amount), '--delay', '80',
      String({ up: 4, down: 5, left: 6, right: 7 }[direction])]);
    return text({ direction, amount });
  });
  return server;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  await createServer().connect(new StdioServerTransport());
}
