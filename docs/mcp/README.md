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
| `capture_region` | Screenshot of a part of the screen (`x,y,width,height` in screen coordinates; decimals are accepted) |
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
  `aiTools.allowedClients`, `aiTools.excludedApplications`, `aiTools.notifyOnCapture`; see docs/admin). The last three
  can only be locked, not given as unlocked defaults: an unlocked value can come from any program of the user, so
  Greenshot ignores it and logs why. When the administrator manages the allowed programs, nobody is asked: other
  programs are refused.
* The app doesn't trust what a connection says about itself. For the source `mcp` the program on the other end of the
  socket must be the `greenshot-mcp` of the same app bundle (a development build: the one next to `GreenshotMac`). When
  the app is signed with a Team ID or a certificate of its own, greenshot-mcp's signature must be intact and by the same
  signer; an ad hoc signed or unsigned build has no signer to compare, so there only the path is checked. greenshot-mcp
  in turn sends nothing to a socket whose program isn't the `GreenshotMac` of its own bundle (greenshot-cli and
  greenshot-native-host check the same). The AI tool is the program that started greenshot-mcp, identified by its
  executable, its arguments and its code signature. A shell or `env` in between is skipped only when it is a system
  program (in `/bin` or `/usr/bin`) that starts greenshot-mcp directly, like `zsh -lc "exec …/greenshot-mcp"`; a shell
  that runs a script file is that script's program (`sh | script: …/configure`), so a script an AI tool runs doesn't
  get the AI tool's consent. An AI tool started through another shell (Homebrew's bash or zsh, fish) must start
  greenshot-mcp itself. A program that starts greenshot-mcp and then turns itself into an allowed program (`exec`) is
  refused.
* Each AI tool must be allowed by you: the first request shows a question with the program's name, path and signer.
  Allowed programs are stored in the settings and can be removed on the AI Tools tab. The allowed programs, the
  excluded applications and the capture notification are sealed with a key in your Keychain: when another program
  edits them in the preferences, Greenshot resets them (nobody allowed, the notification on, the default exclusions
  back) and asks again. "Don't Allow" (or closing the
  question) is remembered until the app quits; the tab lists those programs with "Allow" and "Ask Again". The question
  stays on top but never takes the keyboard, has no default button, ignores Escape and Return, and its buttons react only
  after a second, so a keystroke meant for the AI tool can't answer it. It opens at a slightly different place each time
  and counts "Allow" only when it has been shown unchanged for that second and no other program's window lies over it:
  a click that arrives earlier, or while it is covered, starts the second again. The command line's capture question
  counts its "Allow" the same way. At most three questions are shown a minute; more
  requests are refused until the minute is over. A helper inside an app is shown with the app's name, e.g. "Claude
  (disclaimer)"; the helper's path is what is allowed.
* AI tools that run in a runtime (Node.js, Bun, Deno, Python, Ruby, Perl, PHP, `osascript`, or an Electron app such as
  VS Code switched into Node.js with `ELECTRON_RUN_AS_NODE`) are allowed together with their script: the question shows
  "node" and the script, e.g. Claude Code's `cli.js`, and allowing it doesn't allow any other script that node runs.
  Every option before the script (`--require`, `--import`, `--env-file`, `--inspect`, `-M`, `-I`, …) and the runtime's
  code-loading environment variables (`NODE_OPTIONS`, `NODE_PATH`, `PYTHONPATH`, `PYTHONSTARTUP`, `RUBYOPT`, `RUBYLIB`,
  `PERL5OPT`, `PERL5LIB`, `PHPRC`, …) are part of what is allowed, so a changed option asks again. A runtime running inline code (`node -e`, `python -c`, a script from stdin) is refused, and so is
  every AI tool started with `DYLD_` variables. A signed program is allowed with its Team ID, and the app checks the
  running program's signature on every new greenshot-mcp session, so a copy of the program at the same path signed by
  someone else is asked about again.
* AI tools can only list windows, run recipes with an AI tool trigger and propose recipes, and only through greenshot-mcp:
  not from greenshot-cli, links or the browser extension. AI tools can't run command line recipes, open files, change
  settings or quit the app.
* Window ids instead of window numbers: an AI tool can only capture windows the app listed to it. The ids belong to one
  AI tool and greenshot-mcp session, expire 10 minutes after the last `list_windows` that showed the window, and stop
  working when the window is closed.
* Windows of the excluded applications (password managers and Keychain Access / Passwords by default) never get an id,
  can't be captured, and are blacked out in everything else a recipe started by an AI tool takes from the screen. An
  entry matches an application whose name starts with it ("1Password" matches "1Password 7"), and an entry with a dot
  matches bundle identifiers starting with it (`com.agilebits` matches all of 1Password's helpers). The windows are
  looked up when the run starts and again for the picture, and both are blacked out; when blacking out fails, the
  picture is black altogether. A recipe's recording (RecordVideo) started by an AI tool refuses such a window, and a
  recording of a display or region shows only the other apps: an app that starts during the recording is added within
  a second or so, an excluded one never, and the desktop picture and the Dock stay out of that video.
* Every capture shows a notification (on by default).
* Limits: a program running as you could still take screenshots without Greenshot if it has the screen recording
  permission itself, or control an allowed program. The checks keep web pages, extensions and other programs from using
  Greenshot as a screenshot service, and make sure your consent goes to a named program. A program written to attack
  Greenshot can get further: one that forks, turns itself into an allowed program and lets its child start
  greenshot-mcp looks like that allowed program, and one that deletes and replaces the Keychain key can seal an allowed
  list of its own (macOS lets any program of the user delete a login-keychain item without asking; the recipe
  approvals have the same limit). Closing that needs a Developer ID build, whose keys can live in the data protection
  keychain where other programs can't touch them.

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
  (`npx @modelcontextprotocol/inspector <path of greenshot-mcp>`; the Inspector's node and its script are then the AI
  tool the app asks about), or write JSON-RPC lines to its stdin.
* How it fits together: `Sources/greenshot-mcp` is the stdio transport and the connection to the app (one request per
  tool call with the source `mcp`, the watch connection, the tool sync); the protocol engine and the tools are in Core
  (`MCPServer.swift`, `MCPTools.swift`). In the app, `AIToolsCenter` checks the opt-in and the consent, and handles
  LIST_WINDOWS, LIST_AI_TOOLS, RUN_AI_TOOL, RECIPE_CATALOG, VALIDATE_RECIPE and PROPOSE_RECIPE (Core `AIToolCatalog`,
  `AIRecipeCatalog`, `AIRecipeProposals`); the recipes' Source and RecordVideo steps ask `AIToolsCaptureGuard` about
  excluded applications (RecordVideo's rule: Core `RecipeRecordVideoPlan.aiToolRule`). Tests: `MCPServerTests`,
  `MCPToolsTests`, `MCPConnectionTests`, `AIToolAccessTests`, `AIToolIdentityTests`, `AIWindowRefsTests`,
  `AIToolCaptureTests`, `AIToolRecordingTests`, `AIToolCatalogTests`, `AIRecipeProposalTests`.
