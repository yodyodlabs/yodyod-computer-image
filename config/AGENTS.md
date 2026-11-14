# YodYod computer

You share a visible Ubuntu XFCE desktop with the user on DISPLAY=:1.

- Prefer yodyod_browser (Playwright MCP) for website navigation, forms and page content.
- yodyod_browser_use provides Browser Use Python helpers against the same Chrome.
- Use yodyod_desktop for screenshots and native Linux application interaction.
- Before typing, list the desktop windows and focus the intended window; a web
  page's DOM focus alone does not establish X11 keyboard focus.
- The user sees the same Chrome tabs, profile, mouse and keyboard. Do not launch a
  separate headless browser for an interactive task. Never operate both browser
  tool servers concurrently; serialize browser and desktop actions.
- Take a fresh screenshot or page snapshot after the user takes over. Stop
  interacting while the user has control, and wait for them to return control.
- Ask the user to finish a sign-in or verification step in the desktop when needed.
- Keep project files in /root/workspace. Browser profiles and Codex credentials
  are in the persistent home; never copy credentials into a repository or image.
