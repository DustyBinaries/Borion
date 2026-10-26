# Borion — Native Application Engine

A "Tauri-style" framework for **Delphi 7**: the interface in HTML/CSS/JS running on WebView2, and the
native logic in Delphi, with an `invoke` / `emit` / `listen` bridge between the two. Still under
construction: see the [roadmap](docs/ROADMAP.md).

The [`TWebView2Browser`](WebView2/README.md) control, in `WebView2/`, is the foundation of Borion, but it does not
depend on it and can be used on its own in a regular Delphi 7 app.

```js
const sum = await __BORION__.invoke('somar', { a: 20, b: 22 });   // Delphi command -> 42
```

```pascal
program MeuApp;   // the whole app: no form, the window is assembled by the builder

uses
  Borion, BorionIpc, BorionFs, BorionDialog;

{$R *.res}
{$R web.res}   // the frontend, packed by "borion pack"

procedure Somar(Call: TBorionCall);
begin
  Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
end;

begin
  TBorionBuilder.Create('Meu App')
    .Size(1000, 700)
    .AllowDir('$APPDATA')                 // file scope: denied by default
    .Plugin(TBorionFsPlugin.Create)
    .Plugin(TBorionDialogPlugin.Create)
    .Command('somar', Somar)
    .Run;
end.
```

Borion runs on top of [`TWebView2Browser`](WebView2/README.md) and adds:

- **Form-less app** (`TBorionBuilder`): the whole app written in the `.dpr`, like `tauri::Builder`.
  The window, the IPC and the embedded frontend are assembled by `Run`. See [Creating an app](#creating-an-app).
- **Configuration** (`app.json`): name, version, identifier, the main window and the CSP in a
  file embedded in the exe, like `tauri.conf.json`. See [CONFIG.md](docs/CONFIG.md).
- **Commands**: `__BORION__.invoke(cmd, args)` → Delphi procedure, with the result in a Promise.
- **Errors** with a code: Delphi exception → rejected Promise with `error.code`.
- **Async commands**: `Call.Defer` + `Resolve`/`Reject`, including from other threads.
- **Events** in both directions: `Ipc.Emit` → `__BORION__.listen`; `__BORION__.emit` → `Ipc.Listen`.
- **Origin-based security**: only documents from allowed origins can use the IPC.
- **Correct Unicode** between JS and Delphi 7's ANSI.
- **Frontend embedded in the exe**: `borion pack` packs `dist/` (Vite or any folder) and
  `TBorionAssets` serves it with SPA fallback and standard headers.
- **Dev mode**: `borion dev` opens the app connected to the Vite server (hot-reload) or serving the
  interface folder straight from disk (the page reloads on save), and recompiles and reopens the app
  when the Delphi code changes.
- **CLI**: `borion new` (project from a template), `borion dev` and `borion build`
  (frontend, package, `.rc` and `dcc32` in a single command).
- **Plugins** `dialog`, `fs` and `shell`, with file scope denied by default: the app only touches
  the allowed folders and whatever the user picks in the dialogs.
- **Menus and tray**: `menu` plugins (native menu bar with keyboard shortcuts and context menu),
  `tray` (tray icon, menu and notifications) and `app` (quit, show, minimize).
- **Window**: `window` plugin (title, size, position, maximize, fullscreen, border, always on
  top, events) and `onCloseRequested`, which intercepts closing for an HTML "save changes?"
  prompt. `window-state` makes each window reopen at the size and place where it was closed.
- **Multiple windows**: defined in `app.json` or created by the page (`createWindow`), all on the
  same IPC (plugins and commands serve all of them), with events between them (`emitTo`).
- **Data**: `clipboard` (text and HTML) and `store` (key-value persisted as JSON), with full
  Unicode, including emoji, even though Delphi 7 is ANSI.
- **System and network**: `os` (real Windows version, architecture, language) and `http` (the
  `fetch` done by Delphi, without CORS, with URL scope, timeout and cancellation).
- **Windows integration**: `notification` (native notifications with buttons),
  `single-instance` (the app opens only once and receives the arguments of later runs),
  `deep-link` (`myapp://` links open the app), `autostart` (start with Windows) and
  `global-shortcut` (shortcuts that work while the app is in the background).
- **Log**: `log` to a file with levels and rotation, the same for Delphi and for the page, with the
  page's `console` forwarded.

## Creating an app

The fastest way is the CLI, which generates a project ready to compile:

```bat
Tools\borion.exe new meu-app                      :: plain HTML/JS, no Node
Tools\borion.exe new meu-app --template vite      :: Vite (or --template react)
cd meu-app
borion dev                                        :: the app in dev mode, reloading by itself
borion build                                      :: MeuApp.exe with the interface embedded
```

(With `borion` outside the PATH, the generated `dev.bat` and `build.bat` do the same.)

`borion new <folder> [--template vanilla|vite|react] [--title "Title"] [--port 5173]` creates:

- the `.dpr` with the `TBorionBuilder` and a sample Delphi command;
- the `app.json`, with the name, version, window and where the interface lives ([docs](docs/CONFIG.md));
- the interface (`web\` or `frontend\`);
- `build.bat` and `dev.bat` (shortcuts for `borion build` and `borion dev`);
- the `.rc` with the exe version;
- the `.dof` with the *Search path*, to open in the IDE;
- the `.gitignore` and a README.

The project points to this folder (`BORION_HOME` in `build.bat`). The templates live in
[`Tools/templates`](Tools/templates/README.md).

### `borion dev` and `borion build`

Both take the project folder (default: the current one). They read the [`app.json`](docs/CONFIG.md), if
present, and find the rest by convention:

| What | How it is found |
|---|---|
| Program | The only `.dpr` in the folder |
| Configuration | The `app.json` (optional): validated and embedded in the interface package |
| Interface | The `build.frontendDist` of `app.json`; without it, `frontend\package.json` (npm, outputs to `frontend\dist`) or the `web\` folder (static) |
| Interface package | The first `{$R x.res}` in the `.dpr` (other than `*.res`) |
| *Search path* | The `SearchPath` of the `.dof` |
| Dev server | The `build.devUrl` of `app.json`; without it, the `port:` of `vite.config.js` (default 5173) |
| Delphi | The `DELPHI` variable, else the registry (`Software\Borland\Delphi\7.0`), else the default paths |

**`borion build`:** `npm install` (if `node_modules` is missing) and `npm run build`, or, for a
static interface, copying `@borion/api` to `web\borion-api`; the interface package, with the
`app.json`; `brcc32`, if the `.rc` changed; `dcc32`; and copying `WebView2Loader.dll`. An
invalid `app.json` stops the build; an unknown key only produces a warning.

**`borion dev [--port N] [--no-watch]`:**

- **npm:** starts Vite (`npm run dev -- --port N --strictPort`), waits for it to respond and opens the exe
  with `--dev-url`. Hot-reload is Vite's.
- **static:** opens the exe with `--dev-dir=web`. `TBorionAssets` serves the folder straight from disk
  and reloads the page when a file changes.
- Compiles beforehand only if the sources changed. While running, it watches `*.dpr`, `*.pas`, `*.rc`, `*.inc`
  and `app.json`: on a change, it closes the app, recompiles and reopens it (`--no-watch` turns this off).
- Closing the app ends `borion dev` and Vite along with it (the processes are in a *job object*).

`TBorionBuilder` (unit `Borion`) assembles the app from the `.dpr`, chaining the configuration and
ending in `Run`. It starts from the embedded `app.json`, and the methods called in the `.dpr` override the
file, field by field ([precedence](docs/CONFIG.md#precedência)):

| Method | What it does |
|---|---|
| `TBorionBuilder.Create` / `.Create(Title)` | App and window title: the `productName` from `app.json` or the one given (already applies to plugins created in the same expression) |
| `.Config(C)` | Uses another `TBorionConfig` in place of the embedded one (call right after `Create`) |
| `.Size(W, H)`, `.MinSize(W, H)`, `.MaxSize(W, H)`, `.Maximized` | Window size (default 1000×700, centered) |
| `.Resizable(B)`, `.Centered(B)`, `.Decorations(B)`, `.AlwaysOnTop(B)` | Window border, position and layer |
| `.Csp(policy)` | `Content-Security-Policy` header of the assets |
| `.FixedTitle` | The caption does not follow the page's `document.title` |
| `.Plugin(P)` | Adds a plugin |
| `.Command(name, Proc)` / `.Commands(Register)` | One command (`procedure Proc(Call: TBorionCall)`) or a procedure that registers several (`procedure Register(Ipc: TBorionIpc)`) |
| `.AllowDir(folder)` / `.AllowFile(file)` | The app's file scope, used by the `fs`, `dialog` and `shell` plugins created without a scope |
| `.Url(url)` / `.AllowOrigin(origin)` | Open a URL instead of the embedded frontend; allow one more origin on the IPC |
| `.UserDataFolder(folder)` | WebView2 data folder |
| `.Setup(Proc)` | `procedure Proc(Window: TBorionWindow)`, after the main window is assembled and before the page opens: access to the form, the browser, the IPC and the plugins |
| `.OnCloseQuery(Proc)` / `.OnClose(Proc)` | Confirm or save something on close (apply to all windows; see `Window.WindowLabel`) |
| `.Run` | Runs the app and frees the builder |

- **Plugins with configuration** are created beforehand, in a variable:
  `Tray := TBorionTrayPlugin.Create; Tray.MinimizeToTray := True;` and then `.Plugin(Tray)`.
- **A single instance:** `.Plugin(TBorionSingleInstancePlugin.Create('Company.MyApp'))`. On a
  second run, the plugin hands the arguments to the first and `Run` ends without creating a window.
- The window (`TBorionWindow`) has the browser filling it, the exe's icon, and in dev mode shows the
  server URL in the title.
- The `.dpr` only lists the units the app uses (`Borion` and the plugins); the root of this repository,
  `Plugins/` and `WebView2/` go in the *Search path* (the examples do this in `build.bat` and in the
  `.dof`).

**In an existing form:** to put Borion inside a Delphi app that already has forms, create the
`TWebView2Browser`, the `TBorionIpc` and the `TBorionAssets` in the form itself, as in
[`Examples/Demo`](#examples) and in the [IPC guide](docs/IPC.md#configuração).

## Requirements

- The [WebView2](WebView2/README.md#requisitos) requirements (Delphi 7, WebView2 Runtime,
  `WebView2Loader.dll`).
- **Jsons.pas** (json4delphi, distributed with ACBr). The `build.bat` files look for it in
  `C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src`, and for `ACBr.inc`, which it includes, in
  `C:\dev\lib\ACBr\Fontes\ACBrComum`. For other paths, set the `JSON4DELPHI` and
  `ACBR_COMUM` variables and adjust the project's *Search path* in the IDE (in the example, `BorionDemo.dof`).

## Files

| File | What it is |
|---|---|
| `Borion.pas` | `TBorionBuilder` and `TBorionWindow`: the app assembled from the `.dpr`, without a form |
| `BorionIpc.pas` | `TBorionIpc` (commands, events, origins), `TBorionCall`, `EBorionError` and the injected JS bridge |
| `BorionJson.pas` | Unicode fixes at the JSON boundary between JS and Delphi 7 |
| `BorionAssets.pas` | `TBorionAssets`: serves the embedded frontend (SPA, headers, MIME) and dev mode |
| `BorionPack.pas` | Asset package format, compression and `.res` reading/writing |
| `BorionConfig.pas` | `TBorionConfig`: reading and validating `app.json`, and the `BorionAppConfig` embedded in the exe |
| `WebView2/` | The `TWebView2Browser` control, dependency-free ([README](WebView2/README.md)), with `WebView2Loader.dll`, an example and its own tests |
| `WebView2/docs/WebResourceRequested.md` | Intercepting WebView2 requests |
| `Plugins/` | `TBorionScope` (file scope) and the `fs`, `dialog`, `shell`, `menu`, `tray`, `app`, `window`, `window-state`, `clipboard`, `store`, `os`, `http`, `notification`, `single-instance`, `deep-link`, `autostart`, `global-shortcut` and `log` plugins ([docs](docs/PLUGINS.md)) |
| `Tools/` | `borion` CLI (Delphi console): `borion new` (with the templates in `Tools/templates`), `borion dev`, `borion build`, `borion pack`, `borion list` |
| `js/` | ESM package [`@borion/api`](js/README.md) for apps with a bundler, and `borion.d.ts` (types for `window.__BORION__`) |
| `docs/IPC.md` | Complete IPC guide |
| `docs/ASSETS.md` | Frontend assets, `borion pack`, SPA fallback and dev mode |
| `docs/CONFIG.md` | The `app.json`: key reference, precedence and how it gets into the exe |
| `docs/ROADMAP.md` | Framework roadmap |
| `Examples/Demo/` | Example with all the IPC features, in a traditional Delphi form, plain HTML/JS page (see below) |
| `Examples/ViteReact/` | React + Vite app: build embedded in the exe and dev mode with hot-reload ([README](Examples/ViteReact/README.md)) |
| `Examples/Editor/` | Text editor with Vite + plain JS, made only with the official plugins ([README](Examples/Editor/README.md)) |
| `Examples/Titlebar/` | Borderless window with an HTML title bar: drag, maximize on double-click, resize from the edge and custom buttons ([README](Examples/Titlebar/README.md)) |
| `Examples/Kiosk/` | Kiosk mode: fullscreen, always on top, no DevTools, close blocked by `onCloseRequested` and a hidden PIN exit ([README](Examples/Kiosk/README.md)) |
| `Examples/MultiWindow/` | Multiple windows: one from `app.json` opened on demand, others created by the page, theme and notes exchanged with `emitTo` ([README](Examples/MultiWindow/README.md)) |
| `Examples/Menu/`, `Tray/`, `App/`, `Window/`, `Clipboard/`, `Store/`, `Os/`, `Http/`, `Notification/`, `SingleInstance/`, `DeepLink/`, `Autostart/`, `GlobalShortcut/`, `Log/` | A small example for each plugin, without a bundler ([Menu](Examples/Menu/README.md), [Tray](Examples/Tray/README.md), [App](Examples/App/README.md), [Window](Examples/Window/README.md), [Clipboard](Examples/Clipboard/README.md), [Store](Examples/Store/README.md), [Os](Examples/Os/README.md), [Http](Examples/Http/README.md), [Notification](Examples/Notification/README.md), [SingleInstance](Examples/SingleInstance/README.md), [DeepLink](Examples/DeepLink/README.md), [Autostart](Examples/Autostart/README.md), [GlobalShortcut](Examples/GlobalShortcut/README.md), [Log](Examples/Log/README.md)) |
| `Tests/` | DUnit tests and `run-tests.bat`, which also runs the JS tests (see below) |

To use it in a project: put the root of this repository, `WebView2/` and
`Plugins/`, the folder of `Jsons.pas` and that of `ACBr.inc` in the *Search path*. The examples (except `Demo`) are a
single `.dpr`, with the `TBorionBuilder`.

The Delphi sources are in **ANSI (cp1252) with CRLF**, as Delphi 7 expects. Do not save them in
UTF-8.

## Examples

**[`Examples/Editor/`](Examples/Editor/README.md):** a text editor (open, save, recent files)
with no Delphi commands of its own, only the official plugins. It shows file scope in
practice, the native menu bar with shortcuts, the tray icon and preferences in the `store`.

**[`Examples/Menu/`](Examples/Menu/README.md), [`Tray/`](Examples/Tray/README.md),
[`App/`](Examples/App/README.md), [`Window/`](Examples/Window/README.md),
[`Clipboard/`](Examples/Clipboard/README.md),
[`Store/`](Examples/Store/README.md), [`Os/`](Examples/Os/README.md),
[`Http/`](Examples/Http/README.md), [`Notification/`](Examples/Notification/README.md),
[`SingleInstance/`](Examples/SingleInstance/README.md), [`DeepLink/`](Examples/DeepLink/README.md),
[`Autostart/`](Examples/Autostart/README.md), [`GlobalShortcut/`](Examples/GlobalShortcut/README.md) and
[`Log/`](Examples/Log/README.md):** an isolated example for each plugin, with a plain HTML/JS
page and the whole app in a `.dpr` of a few lines (`TBorionBuilder`). They show everything the plugin does: menu bar,
shortcuts, `update` and `popup`; icon, menu, notifications and minimizing to the tray; `app.info`,
minimize, hide and quit going through `OnCloseQuery`; the window controlled by the page, with
fullscreen, border and an HTML "save changes?" on close; copying and pasting text with emoji and
copying HTML; preferences that survive between runs, including the window position,
written by Delphi to the same store; the real Windows version; Borion's `fetch` fetching,
side by side, a page that the browser's `fetch` cannot reach because of CORS; native notifications with
buttons; the app that opens only once and receives the arguments of later runs; `borion-exemplo://`
links opening the app; starting with Windows; global shortcuts with the app
in the background; and the Delphi and page logs in the same file.

**[`Examples/Titlebar/`](Examples/Titlebar/README.md):** borderless window (`"decorations": false`)
with an HTML title bar, like Tauri's: drags by elements with
`data-borion-drag-region`, maximizes on double-click, resizes from the edge of the page and has
minimize, maximize and close buttons made in the page.

**[`Examples/MultiWindow/`](Examples/MultiWindow/README.md):** multiple windows. The main one lists
the open ones, opens the settings window (defined in `app.json`, with `"create": false`) and creates notes
(windows that are not in `app.json`). The settings change the theme of all of them with
`emitTo('*', ...)`, and the notes send their text to the main one with `emitTo('main', ...)`. A single
Delphi command answers all of them, knowing which one it came from.

**[`Examples/ViteReact/`](Examples/ViteReact/README.md):** a React app with Vite. `build.bat`
generates a single exe with the frontend embedded; `dev.bat` opens the app connected to the Vite server,
with hot-reload.

**`Examples/Demo/`:** shows Borion inside a traditional Delphi form, without a bundler. The Delphi window has only the
browser and a log panel; the whole interface is the `web\` page (plain HTML/JS, packed by
`borion pack`), and the native logic is the commands in `uComandos.pas`, written as standalone
procedures.

| Page section | What it demonstrates |
|---|---|
| 1. Commands | `somar`, `saudacao` (Unicode in both directions), `info` (object), `listarArquivos` (array) |
| 2. Errors | `EBorionError`, validation, nonexistent command and `timeout` in JS |
| 3. Async command | `tarefaLonga`: `Call.Defer`, thread, progress events, `Resolve` |
| 4. Events | `__BORION__.emit` → window log; the window's "Emit" button → `__BORION__.listen` |
| 5. Security | Origin allowed with `AllowOrigin`; others get `FORBIDDEN_ORIGIN` |

Open `BorionDemo.dpr` in the IDE, or from the command line:

```bat
Examples\Demo\build.bat
```

**[`WebView2/Examples/Demo/`](WebView2/README.md):** just the control, without Borion: a browser with
all the features of `TWebView2Browser`.

```bat
WebView2\Examples\Demo\build.bat
```

## Tests

```bat
Tests\run-tests.bat
```

Runs **313 DUnit tests** and **76 JS tests** (`node:test`):

- DUnit: `BorionJson` Unicode, `TBorionIpc` routing without WebView2, and the asset
  package and `TBorionAssets` (compression, UTF-8 paths, `.res`, SPA fallback, headers,
  dev mode);
  and the plugins (scope against `..`, neighboring prefix, devices and streams; all of `fs` through the IPC,
  including a junction pointing outside the scope; `shell` policy; `Ipc.Later`; menu
  built from JSON, shortcuts and popup; tray with `Shell_NotifyIcon` captured; `app`;
  `window` (size, limits, borders, fullscreen, events and intercepted closing, with and without
  a response from the page); multiple windows (responses and events to the right window, `emitTo`, the
  notices to plugins and `window` with two windows on the same IPC); `window-state` (save and
  restore, maximized, fullscreen, disconnected monitor, corrupted file, without recreating the window);
  `clipboard` with the real clipboard and emoji; `store` with a corrupted file,
  hand-edited and without `AutoSave`; ASCII-only JSON; `os`; `http` against a local
  HTTP server: scope, redirects, timeout, cancellation, binary and limits; XML and events of
  `notification`; delivery of `single-instance` arguments with Unicode; registration of
  `deep-link` and `autostart` in HKCU, with a Unicode path and the Task Manager's "Disabled";
  global shortcuts (syntax, conflict with another program, WM_HOTKEY); log with levels,
  rotation, several threads and Unicode; the `TBorionBuilder` and the app's file scope; the `app.json`
  (types, values, warnings, UTF-8, the resource in the `.res` and its application in the builder and window); the
  `borion new` with the real templates; `borion build` project detection, with and without
  `app.json`, and a real build of a generated project);
- JS: the real bridge, the `@borion/api` package and the `dialog`, `fs`, `shell`, `menu`, `tray`, `app`, `window`, `window-state`, `clipboard`, `store`, `os`, `http`, `notification`,
  `single-instance`, `deep-link`, `autostart`, `global-shortcut` and `log` modules.
It needs [DUnit](https://dunit.sourceforge.net/) (`DUNIT` variable, default
`C:\dev\lib\dunit\src`) and Node.js 18+. Details in the [IPC guide](docs/IPC.md#testes).
