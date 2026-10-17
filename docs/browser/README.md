# Browser extension

The Greenshot for Mac (Community) Companion is the Mac copy of upstream Greenshot's browser extension
(`src/Greenshot.BrowserExtension`) for Chrome, Edge and Firefox (Brave, Vivaldi and Chromium work like Chrome). It is
unofficial, like the app, and has its own ids, so it doesn't talk to Greenshot for Windows and upstream's extension
doesn't talk to this app. Safari isn't supported yet.

What it does:
- **Capture Visible Page** in its popup takes the visible part of the current tab and sends it, with the page's title
  and address, to the app. The app asks where it goes with the destination picker (or a recipe with an Extension
  trigger takes it). File names can use `${url}` and `${browser}` of the page.
- **QA tab URL tracking** (on by default, switch it off on the extension's options page): the extension tells the app
  the address and title of the active tab. File names can then use `${Browser.Url}`, `${Browser.Domain}`,
  `${Browser.Title}` and `${Browser.Ticket}` (a key like `PROJ-1234` from the title or the address), e.g. an output
  folder pattern `${Browser.Ticket}` sorts screenshots by ticket. The app keeps only the last tab, in memory, and never
  writes addresses or titles into its log.
- These values come from web pages, so in file names and folders they are cleaned like `${title}`: `/`, `:` and the
  other characters a file name can't have become `_` (`https://x.org/a` gives `https___x.org_a`). A page can't choose
  the folder a screenshot goes to: a file name that would leave the output folder is made one name inside it, and an
  output folder pattern like `~/Shots/${title}` that would end up outside `~/Shots` saves to `~/Shots`.
- The toolbar button shows ON while the app is connected. When the app isn't running the extension tries again (after
  5 s, then up to every minute); it never starts the app.

## Install

1. In the app: Settings › Expert › Browser extension › **Install**. This lets the browsers found on the Mac start
   `greenshot-native-host` (in the app bundle, `Contents/Helpers`) for the extension: one file
   `io.github.greenshot_mac.host.json` in each browser's `~/Library/Application Support/<browser>/NativeMessagingHosts`
   folder. **Remove** deletes them again. Moving the app is noticed at the next start; a line that says "Installed for
   another copy of the app" means another copy registered itself, click Install to use this one.
2. **Show Extension Folder…** copies the extension to `~/Library/Application Support/io.github.greenshot-mac.GreenshotMac/BrowserExtension`
   and shows it in Finder.
3. Chrome, Edge, Brave, Vivaldi: open the Extensions page (`chrome://extensions`, `edge://extensions`), turn on
   Developer mode, click **Load unpacked** and choose that folder. The extension's id is
   `phnpiifkcghdmpcgjilfkdlaidfjjjea` in every Chromium browser (fixed by the `key` in its manifest).
4. Firefox 126 or later: `about:debugging` › This Firefox › **Load Temporary Add-on…** and choose `manifest.json` in
   that folder. Firefox keeps an add-on that isn't signed by Mozilla only until it quits (Firefox Developer Edition and
   Nightly can keep it with `xpinstall.signatures.required` set to false).

The extension asks for no access to the sites you visit: "activeTab" lets it capture the tab you clicked its button in,
"tabs" gives it the active tab's address and title for the tab tracking (upstream also asks for `<all_urls>`).

The extension isn't in the Chrome Web Store or on addons.mozilla.org. Its Firefox id `companion@greenshot-mac.github.io`
isn't reserved on addons.mozilla.org yet, so someone else could publish a signed add-on with the same id, and the app
would accept it like this one (it could send screenshots and tab addresses; the checks above still apply). Reserving the
id (an unlisted, signed listing) is up to the project's maintainers. `scripts/package-browser-extension.sh` zips it
into `build/browser-extension/greenshot-mac-companion-<version>.zip` (manifest.json at the root), e.g. for a release.

## How it connects

```
extension ──native messaging (stdin/stdout)──> greenshot-native-host ──socket──> Greenshot for Mac
```

- The browser starts `greenshot-native-host` with the extension's origin (`chrome-extension://<id>/`, or for Firefox
  the host manifest's path and the add-on id). The host announces itself to the app as `native_messaging` with that
  origin and relays the messages unchanged, both ways: 4-byte little-endian length + JSON, as upstream's
  `greenshot-proxy` (docs/greenshot-proxy-and-integration.md §2.1).
- The app accepts the host only as the program in its own bundle (code signature checked), only the commands
  `HANDSHAKE`, `IMPORT_CAPTURE` and `TAB_CHANGED` from it, and only from the Mac extension's ids plus what the installed
  host manifests allow. A developer's own build of the extension: add its origin to `allowed_origins` (Chromium) or its
  id to `allowed_extensions` (Firefox) in the installed manifest; Install keeps such entries.
- Settings › Expert › Browser extension › "Allow the browser extension to send screenshots" switched off refuses every
  request (an administrator can lock it: `browserExtensionEnabled`).
- `IMPORT_CAPTURE` accepts only PNG and JPEG (checked by their first bytes), at most 32767 pixels per side and 100
  megapixels, read from the image's header before anything is decoded, and only a complete file. The extension gets
  `{"status":"ok","reply_to":"IMPORT_CAPTURE","width":…,"height":…}` or `{"status":"error",…,"stderr":"Error: …"}`.

Differences from upstream's extension (each marked in the source):
- the host name `io.github.greenshot_mac.host`, the Firefox id `companion@greenshot-mac.github.io` and the Chromium
  `key`;
- no `host_permissions` (`<all_urls>`): `activeTab` and `tabs` are enough, so Firefox needs version 126;
- `IMPORT_CAPTURE` and `TAB_CHANGED` also send `browser` (upstream sends it only with `HANDSHAKE`, so its `${browser}`
  stays empty), and `IMPORT_CAPTURE` the tab's width, so the app knows a Retina capture's scale;
- the app's `HANDSHAKE` answer leaves out `capture_format` and `track_tab_urls`: upstream always answers PNG and
  tracking on, which overwrote the choices on the extension's options page at every reconnect.

## Trying it without a browser

The host speaks on stdin/stdout, so a script can play the browser (the app must be running):

```sh
python3 - "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-native-host" <<'EOF'
import json, struct, subprocess, sys
host = subprocess.Popen([sys.argv[1], "chrome-extension://phnpiifkcghdmpcgjilfkdlaidfjjjea/"],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)
message = json.dumps({"command": "HANDSHAKE", "extension_version": "1.0.0", "browser": "chrome"}).encode()
host.stdin.write(struct.pack("<I", len(message)) + message)
host.stdin.flush()
length = struct.unpack("<I", host.stdout.read(4))[0]
print(host.stdout.read(length).decode())
host.stdin.close()
EOF
```
