# greenshot-mcp: Greenshot for Mac for AI tools

`greenshot-mcp` lets AI tools (Claude Code, Claude Desktop, VS Code, Cursor and other MCP clients) see your windows
through Greenshot for Mac (Community), an unofficial macOS port of Greenshot. It is a small
[Model Context Protocol](https://modelcontextprotocol.io) server over stdio that comes inside the app
(`Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp`) and talks to the running app over the same
automation socket as `greenshot-cli`. It is the Mac version of upstream's `greenshot-mcp.exe`
(upstream `docs/mcp-server.md`).

## Tools

| Tool | What it does |
|---|---|
| `list_windows` | The windows on the screen, front to back (id, title, application, bundle id, bounds, active), and the displays with their bounds and scale |
| `capture_window` | Screenshot of one window by its id from `list_windows`, with its exact contents (also when it is covered), without activating it |
| `capture_region` | Screenshot of a part of the screen (`x,y,width,height` in screen coordinates) |
| `capture_screen` | Screenshot of all displays |
| `get_recipe_schema` | The recipe JSON schema and example recipes (also the resource `greenshot-mcp://recipes/schema`) |
| `get_recipe_catalog` | What recipes can use here: trigger types, step types with their parameters, destinations (uploads marked), processors, your recipes; with `recipe_id` the JSON of one recipe |
| `validate_recipe` | Checks a recipe: errors, warnings, what it does in plain words and what you will be asked to allow |
| `propose_recipe` | Shows a new recipe to you; you decide whether it is saved |
| `update_recipe` | Shows a changed version of an existing recipe (also a built-in one) with the changed lines |
| your recipes | Every recipe with an enabled **AI tool** trigger |

Screen coordinates are points with the origin at the top left of the main display, the space of `list_windows`. Each
capture tool takes `ocr=true` to also return the recognized text and the position of each line (pixels of the full-size
picture). Pictures are scaled to 1568 pixels on the longest side (the trigger's `MaxImageSize`, 0 keeps the size).
`list_windows` lists the windows on the screen: minimized windows and windows on other Spaces are not listed.

The three capture tools are built-in recipes with an AI tool trigger, so they are there while recipes are switched on
(Settings › Recipes). Recipes with an AI tool trigger become tools as described upstream ("Recipes as tools"):
`ToolName`, `Title`, `Description`, `ReadOnly` / `Destructive`, `Arguments` (with the AI-only types `Window` and
`Region`) and `MaxImageSize`. greenshot-mcp keeps a watch connection to the app: when the recipes or the AI tools switch
change, it updates its tools at once and tells the AI tool (`notifications/tools/list_changed`); it also checks every
30 seconds and after each tool call.

When the app quits it tells greenshot-mcp why: after `exit` (you quit it) greenshot-mcp keeps running and its tools
answer that Greenshot for Mac was closed, until you start it again; nothing starts the app behind your back. When the
app is updated or deleted (greenshot-mcp's own file is replaced or gone) greenshot-mcp exits, so the AI tool starts the
new one.

## Recipes written by AI tools

An AI tool can write a recipe for you: it reads the schema and the catalog, checks its recipe with `validate_recipe`, and
calls `propose_recipe` (or `update_recipe`) with the recipe, your request and its explanation. The recipe approval window
shows it as proposed by an AI tool, with the program's name, path and signer, and the request and explanation as the
AI tool's own words; "What it does" is written by Greenshot from the recipe itself. Every trigger and every permission
(uploads, external programs, files) starts switched off. Greenshot saves only what it showed, in
`~/Library/Application Support/<bundle id>/Recipes/AI/<id>.gsrecipe.json`, and the approval (hash, switched-on
triggers, permissions, "written by") in its signed trust store. A rejected proposal isn't shown again until the app
restarts, and one proposal is shown at a time. "Open in the recipe editor after saving" opens the saved file.

Settings › AI Tools › Approved recipes lists the recipes from files, who wrote them and their approval, with Details,
Review and Revoke.

## Safety

* AI tools are opt-in: until "Let AI tools use Greenshot" is switched on (Settings › AI Tools, off by default), the app
  refuses every greenshot-mcp request without asking; only the version check answers, so the AI tool can tell you how to
  switch it on. "Let AI tools propose recipes" switches off proposals alone. An administrator can set or lock every
  switch and list with a configuration profile (`aiTools.enabled`, `aiTools.allowRecipeProposals`,
  `aiTools.allowedClients`, `aiTools.excludedApplications`, `aiTools.notifyOnCapture`; see docs/admin). When the
  administrator manages the allowed programs, nobody is asked: other programs are refused.
* The app doesn't trust what a connection says about itself. For the source `mcp` the program on the other end of the
  socket must be the `greenshot-mcp` of the same app bundle (a development build: the one next to `GreenshotMac`), with
  an intact signature by the app's own signer. The AI tool is the program that started greenshot-mcp (shells like `zsh`
  or `env` in between are skipped), identified by its executable and its code signature.
* Each AI tool must be allowed by you: the first request shows a question with the program's name, path and signer.
  Allowed programs are stored in the settings and can be removed on the AI Tools tab. "Don't Allow" (or closing the
  question) is remembered until the app quits; the tab lists those programs with "Allow" and "Ask Again". The question
  stays on top but never takes the keyboard, has no default button, ignores Escape and Return, and its buttons react only
  after a second, so a keystroke meant for the AI tool can't answer it. A helper inside an app is shown with the app's
  name, e.g. "Claude (disclaimer)"; the helper's path is what is allowed. An AI tool running in Node.js shows up as
  "node".
* AI tools can only list windows, run recipes with an AI tool trigger and propose recipes, and only through greenshot-mcp:
  not from greenshot-cli, links or the browser extension. AI tools can't run command line recipes, open files, change
  settings or quit the app.
* Window ids instead of window numbers: an AI tool can only capture windows the app listed to it. The ids belong to one
  AI tool and greenshot-mcp session, expire 10 minutes after the last `list_windows` that showed the window, and stop
  working when the window is closed.
* Windows of the excluded applications (password managers and Keychain Access / Passwords by default) never get an id,
  can't be captured, and are blacked out in everything else a recipe started by an AI tool takes from the screen.
* Every capture shows a notification (on by default).
* Limits: a program running as you could still take screenshots without Greenshot if it has the screen recording
  permission itself, or control an allowed program. The checks keep web pages, extensions and other programs from using
  Greenshot as a screenshot service, and make sure your consent goes to a named program.

## Install

Nothing to install: greenshot-mcp is in the app, in `Contents/Helpers`. Settings › AI Tools shows its path (Copy Path)
and the setup for each AI tool below (Copy). Switch on "Let AI tools use Greenshot" there first.

## Connect an AI tool

Every MCP client starts greenshot-mcp itself (stdio), so it only needs its path. The examples use the app in
`/Applications`; quote the path, it contains spaces. Restart the AI tool or reload its MCP servers after changing a
configuration file. Settings › AI Tools copies each of these with the path of your copy of the app.

### Claude Code

```
claude mcp add --scope user greenshot -- '/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp'
```

`--scope user` makes it available in all projects. Check it with `claude mcp list` or `/mcp`. For a team, the same in
the project's `.mcp.json`:

```json
{
  "mcpServers": {
    "greenshot": { "command": "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp" }
  }
}
```

### Claude Desktop

Settings › Developer › Edit Config opens `~/Library/Application Support/Claude/claude_desktop_config.json`. Add the
`mcpServers` entry above and restart Claude.

### Cursor and Windsurf

The same `mcpServers` entry, in `~/.cursor/mcp.json` (all projects) or `.cursor/mcp.json` (one project) for Cursor, and
in `~/.codeium/windsurf/mcp_config.json` for Windsurf.

### VS Code (GitHub Copilot agent mode)

Run "MCP: Add Server" (Command (stdio), the path, name `greenshot`), or in `.vscode/mcp.json` of the workspace:

```json
{
  "servers": {
    "greenshot": {
      "type": "stdio",
      "command": "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp"
    }
  }
}
```

### Gemini CLI

```
gemini mcp add --scope user greenshot '/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp'
```

or the `mcpServers` entry in `~/.gemini/settings.json`. Check it with `/mcp`.

### Google Antigravity

The `mcpServers` entry (with `"args": []`) in `~/.gemini/config/mcp_config.json` (the agent panel's `…` menu › MCP
Servers › Manage MCP Servers › View raw config), then Refresh.

### OpenAI Codex

```
codex mcp add greenshot -- '/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp'
```

or in `~/.codex/config.toml`:

```toml
[mcp_servers.greenshot]
command = '/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp'
```

### Other MCP clients

Any client that supports local (stdio) MCP servers works: the command is the path of greenshot-mcp, without arguments or
environment variables. greenshot-mcp speaks both protocol eras: the `initialize` handshake of the revisions up to
2025-11-25, and the per-request revision 2026-07-28 (`server/discover`, `subscriptions/listen`).

## Use it

Ask the AI tool in your own words, for example:

* "Look at my Xcode window and tell me what the error says." (`list_windows`, then `capture_window`)
* "Take a screenshot of the region with the chart and read the numbers." (`capture_region` with OCR)
* "Make a recipe: ⇧⌘U captures a region, adds a red border and copies it to the clipboard." The AI tool writes the
  recipe, checks it and proposes it; you decide.
* "Add a tool that captures the active window and returns the text." The AI tool proposes a recipe with an AI tool
  trigger; after you approve it, the AI tool has the new tool.

## For developers

* Build: `swift build` builds `greenshot-mcp` next to `GreenshotMac` (`.build/debug`); `scripts/build-app.sh` puts it into
  the app (`Contents/Helpers`, signed with the identifier `<bundle id>.mcp`) together with `recipe.schema.json` and
  `Resources/RecipeExamples` (the examples `get_recipe_schema` sends).
* A development build of greenshot-mcp never starts the app: start `GreenshotMac` first (for experiments with
  `--settings-dir <folder>`, so your settings stay untouched). It is accepted because it lies next to `GreenshotMac`.
* `greenshot-mcp --help` / `--version`; `GREENSHOT_MCP_DEBUG=1` adds information lines on stderr (stdout is the
  protocol).
* To try the tools without an AI tool, use the [MCP Inspector](https://github.com/modelcontextprotocol/inspector)
  (`npx @modelcontextprotocol/inspector <path of greenshot-mcp>`; the Inspector's node is then the AI tool the app asks
  about), or write JSON-RPC lines to its stdin.
* How it fits together: `Sources/greenshot-mcp` is the stdio transport and the connection to the app (one request per
  tool call with the source `mcp`, the watch connection, the tool sync); the protocol engine and the tools are in Core
  (`MCPServer.swift`, `MCPTools.swift`). In the app, `AIToolsCenter` checks the opt-in and the consent, and handles
  LIST_WINDOWS, LIST_AI_TOOLS, RUN_AI_TOOL, RECIPE_CATALOG, VALIDATE_RECIPE and PROPOSE_RECIPE (Core `AIToolCatalog`,
  `AIRecipeCatalog`, `AIRecipeProposals`); the recipes' Source step asks `AIToolsCaptureGuard` about excluded
  applications. Tests: `MCPServerTests`, `MCPToolsTests`, `AIToolAccessTests`, `AIWindowRefsTests`, `AIToolCaptureTests`,
  `AIToolCatalogTests`, `AIRecipeProposalTests`.
