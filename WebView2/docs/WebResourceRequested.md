# Intercepting requests with `OnWebResourceRequested`

*Leia em português: [WebResourceRequested_pt-BR.md](WebResourceRequested_pt-BR.md).*

This document describes how `TWebView2Browser` intercepts page requests so that Delphi can answer
in place of the network. This is how the page embedded in the executable and the demo's "local
API" work.

- [Overview](#overview)
- [Request flow](#request-flow)
- [Filters](#filters)
- [The event](#the-event)
- [Reference: `TWV2WebResourceRequest`](#reference-twv2webresourcerequest)
- [Reference: `TWV2WebResourceResponse`](#reference-twv2webresourceresponse)
  ([deferred response](#deferred-response))
- [Recipes](#recipes)
- [Errors and exceptions](#errors-and-exceptions)
- [Caveats and limitations](#caveats-and-limitations)
- [Under the hood](#under-the-hood)

## Overview

WebView2 only notifies the application about requests whose address matches a registered
**filter**. For each of them, `TWebView2Browser` fires `OnWebResourceRequested`, and your code
chooses between two outcomes:

- **answer in Delphi**: build the response (status, headers, content) and set
  `Handled := True`. Nothing goes out to the network;
- **let it through**: leave `Handled` alone. The request proceeds normally, and you may change
  its headers first.

Typical uses:

| Use | How |
|---|---|
| Local API for the UI (no HTTP server) | Answer `https://app.localhost/api/...` with JSON |
| Page embedded in the executable | `ServeEmbeddedResources`, which uses this same mechanism |
| Inject authentication into calls to a server | `Request.SetHeader('Authorization', ...)` without setting `Handled` |
| Block resources (ads, trackers, images) | Answer 403/204 for the unwanted patterns |
| Serve files from disk during development | `Response.LoadFromFile(...)` |

## Request flow

```
the page makes a request (navigation, <script>, <img>, fetch, XHR...)
        │
        ▼
does the URL match any filter? ── no ──► network (Delphi never hears about it)
        │ yes
        ▼
OnWebResourceRequested(Request, Response, Handled)
        │
        ├─ Handled = True ─────────────────────────► sends Response
        │
        ▼ Handled = False
is it the ServeEmbeddedResources host? ── yes ──► RCDATA resource (or 404) ──► sends
        │ no
        ▼
network (with whatever headers the event changed)
```

The event runs **before** the embedded resource server. That is why it can handle paths on the
same host (`api/...`) and even override an embedded file. Whatever it does not handle keeps being
served from inside the executable.

## Filters

```pascal
procedure AddWebResourceRequestedFilter(const UriPattern: WideString;
  ResourceContext: Integer = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
```

- `UriPattern` accepts the `*` wildcard, for example `https://api.example.com/*` or `*.png`.
- It may be called **before** `CreateWebView`: the filter stays pending and is applied as soon as
  the browser is ready.
- `ServeEmbeddedResources('app.localhost')` already registers `https://app.localhost/*`.
- `RemoveWebResourceRequestedFilter(Pattern, [Context])` removes a filter (the pattern and
  context must be the same ones used when registering); `ResourceFilterCount` tells how many
  there are.

`ResourceContext` restricts the filter to one kind of resource. The unit only declares the
constant `COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL`; the other values can be passed as numbers:

| Value | Context | Value | Context |
|---|---|---|---|
| 0 | `ALL` | 9 | `TEXT_TRACK` |
| 1 | `DOCUMENT` | 10 | `EVENT_SOURCE` |
| 2 | `STYLESHEET` | 11 | `WEBSOCKET` |
| 3 | `IMAGE` | 12 | `MANIFEST` |
| 4 | `MEDIA` | 13 | `SIGNED_EXCHANGE` |
| 5 | `FONT` | 14 | `PING` |
| 6 | `SCRIPT` | 15 | `CSP_VIOLATION_REPORT` |
| 7 | `XML_HTTP_REQUEST` | 16 | `OTHER` |
| 8 | `FETCH` | | |

Prefer narrow filters: every filtered request goes through the UI thread (see
[Caveats and limitations](#caveats-and-limitations)).

## The event

```pascal
TWV2WebResourceRequestedEvent = procedure(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse;
  var Handled: Boolean) of object;
```

| Parameter | Description |
|---|---|
| `Request` | The intercepted request. Only valid during the event: do not keep the reference |
| `Response` | The response to send. Starts as `200 OK`, with no headers and no content |
| `Handled` | Starts `False`. `True` sends `Response`; `False` lets the request proceed |

Minimal example:

```pascal
FBrowser.ServeEmbeddedResources('app.localhost');
FBrowser.OnWebResourceRequested := BrowserWebResourceRequested;
FBrowser.CreateWebView;

procedure TfrmMain.BrowserWebResourceRequested(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse; var Handled: Boolean);
begin
  if Request.Path = 'api/time' then
  begin
    Response.SetJson('{"time":"' + FormatDateTime('hh:nn:ss', Now) + '"}');
    Handled := True;
  end;
end;
```

```js
fetch('api/time').then(r => r.json()).then(d => console.log(d.time));
```

## Reference: `TWV2WebResourceRequest`

| Member | Type | Description |
|---|---|---|
| `Uri` | `WideString` | Full URL, e.g. `https://app.localhost/api/echo?origin=demo` |
| `Method` | `WideString` | `GET`, `POST`, `PUT`, `DELETE`... |
| `Path` | function | Path without scheme, host, query and fragment, decoded (`%XX` as UTF-8): `https://app.localhost/a%20b/x` → `a b/x` |
| `RawPath` | function | The same, as it came in the URL: `a%20b/x` |
| `QueryParam(Name)` | function | Decoded value of a parameter (`+` becomes a space); `''` if absent |
| `HasQueryParam(Name)` | function | Does the parameter exist (even if empty or without `=`)? |
| `Query` | function | What follows the `?`, without it and **not decoded**: `origin=demo`. Decoding the whole query would break values containing `%26` (`&`) or `%3D` (`=`); use `QueryParam` |
| `GetHeader(Name)` | function | Value of a request header, or `''` if it does not exist |
| `SetHeader(Name, Value)` | procedure | Creates or replaces a header of the request that **goes on to the network** |
| `RemoveHeader(Name)` | procedure | Removes a header of the request that goes on to the network |
| `Content` | `string` | Body (POST/PUT) as raw bytes. Empty if there is none |
| `ContentText` | `WideString` | The body decoded from UTF-8 |
| `ResourceContext` | `Integer` | Resource kind (table in [Filters](#filters)) |
| `Native` | `ICoreWebView2WebResourceRequest` | The original COM interface, for whatever was not wrapped |

Notes:

- The body is read only once, the first time `Content` or `ContentText` is accessed.
- `SetHeader` and `RemoveHeader` only make sense when the event does **not** handle the request.
  If you answer with `Handled := True`, the request never goes out and the changed headers are
  discarded.

## Reference: `TWV2WebResourceResponse`

| Member | Description |
|---|---|
| `StatusCode` | HTTP status. Default `200` |
| `ReasonPhrase` | Status text. Default `OK`. Set it together with `StatusCode` (`404` / `Not Found`) |
| `SetText(Text, [ContentType])` | Stores the text as UTF-8 and sets `Content-Type: <type>; charset=utf-8`. Default `text/plain` |
| `SetJson(Json)` | Shortcut for `SetText(Json, 'application/json')` |
| `SetData(Ptr, Size, ContentType)` | Copies a memory block (binary) |
| `LoadFromStream(Stream, ContentType)` | Copies the whole stream, from position 0 |
| `LoadFromFile(File, [ContentType])` | Loads a file. Without `ContentType`, it is deduced from the extension |
| `SetHeader(Name, Value)` | Sets a response header |
| `Headers` | `TStringList` in `Name=Value` format, for direct manipulation |
| `Content` | `TMemoryStream` with the body, for direct writing |
| `HeadersText` | The headers in the format sent to WebView2 (`Name: Value` separated by CRLF) |
| `Defer` / `Complete` / `Deferred` | Deferred response (see below) |

Types deduced from the extension (`LoadFromFile` and embedded resources): `html`/`htm`, `css`,
`js`/`mjs`, `json`, `txt`, `svg`, `png`, `jpg`/`jpeg`, `gif`, `webp`, `ico`, `woff`/`woff2`,
`wasm`. Anything else becomes `application/octet-stream`.

### Deferred response

The event runs on the UI thread. For a response that depends on slow work (a query, a
calculation in a thread), defer it:

```pascal
procedure TForm1.BrowserWebResourceRequested(Sender: TObject; Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse; var Handled: Boolean);
begin
  if Request.Path = 'api/report' then
  begin
    Response.Defer;                              // asks WebView2 to defer
    Handled := True;
    TReport.Create(Response, Request.QueryParam('month'));   // copy whatever you need from Request
  end;
end;

{ when finished, ON THE UI THREAD (e.g. in the thread's Synchronize): }
Response.SetJson(Json);
Response.Complete;                               // sends and frees the object
```

- `Defer` is only valid inside `OnWebResourceRequested`, and `Complete` only after `Defer`;
  otherwise they raise `EWebView2Error`.
- `Request` is freed at the end of the event. Copy the values you need beforehand.
- Several responses can be deferred at the same time, and the page keeps responding.
- An exception in the event after `Defer` answers 500 immediately and ends the deferral.
- Deferred responses still pending when the WebView is freed or recreated are discarded: do not
  call `Complete` on them afterwards.

> **Strings in Delphi 7:** `SetText` and `SetJson` take `WideString`. Literals and `string`
> (ANSI) variables are converted using the system code page (cp1252 on Windows in Portuguese),
> so accented characters in source-code literals reach the page correctly.

## Recipes

### Local API with routes

```pascal
procedure TfrmMain.BrowserWebResourceRequested(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse; var Handled: Boolean);
var
  Path: WideString;
begin
  Path := Request.Path;
  if Copy(Path, 1, 4) <> 'api/' then
    Exit;  { not the API: proceeds to the embedded resources }
  Handled := True;

  if (Path = 'api/customers') and (Request.Method = 'GET') then
    Response.SetJson(CustomersAsJson)
  else if (Path = 'api/customers') and (Request.Method = 'POST') then
  begin
    SaveCustomer(Request.ContentText);  { JSON body sent by the page }
    Response.StatusCode := 201;
    Response.ReasonPhrase := 'Created';
  end
  else
  begin
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    Response.SetJson('{"error":"unknown route"}');
  end;
end;
```

Page side:

```js
fetch('api/customers', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'São João Bakery' })
}).then(r => console.log(r.status));   // 201
```

The example (`Examples/Demo/uPrincipal.pas`) has the routes `api/clientes`, `api/hora`,
`api/eco` (which returns the POST body, `Content-Type` and query) and `api/erro` (which
deliberately generates a 500).

### Building JSON safely

Delphi 7 has no JSON library. To insert variable text, escape quotes, backslashes and control
characters. The demo uses this function:

```pascal
function JsonStr(const S: WideString): WideString;  { returns the text quoted and escaped }
...
Response.SetJson('{"name":' + JsonStr(Edit1.Text) + '}');
```

### Injecting an authentication header

```pascal
FBrowser.AddWebResourceRequestedFilter('https://api.example.com/*');

{ in the event: }
if Pos('https://api.example.com/', Request.Uri) = 1 then
  Request.SetHeader('Authorization', 'Bearer ' + FToken);
{ Handled stays False: the request proceeds, now carrying the header }
```

The token stays in Delphi and never shows up in the page's JavaScript.

> This recipe has not been tested: the prototype does not call any external server.

### Blocking a resource type

```pascal
FBrowser.AddWebResourceRequestedFilter('*', 3);  { 3 = IMAGE }

{ in the event: }
if Request.ResourceContext = 3 then
begin
  Response.StatusCode := 403;
  Response.ReasonPhrase := 'Forbidden';
  Handled := True;
end;
```

### Serving from disk during development

To edit HTML/CSS/JS without recompiling `web.res`, serve the `web\` folder straight from disk
and leave the embedded resources for the final version:

```pascal
function ServeFromDisk(Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse): Boolean;
var
  RelPath, FileName: string;
begin
  Result := False;
  RelPath := Request.Path;
  if (RelPath = '') or (Pos('..', RelPath) > 0) then
    Exit;  { do not let the page escape the web\ folder }
  FileName := ExtractFilePath(ParamStr(0)) + 'web\' +
    StringReplace(RelPath, '/', '\', [rfReplaceAll]);
  if FileExists(FileName) then
  begin
    Response.LoadFromFile(FileName);
    Result := True;
  end;
end;

{ in the event: }
{$IFDEF WEB_FROM_DISK}
if not Handled then
  Handled := ServeFromDisk(Request, Response);
{$ENDIF}
```

Define `WEB_FROM_DISK` in *Project › Options › Directories/Conditionals* (or `-DWEB_FROM_DISK`
on `dcc32`) only in development builds. Delphi 7 does not define a `DEBUG` symbol by itself.

Since the event runs before the embedded resources, the file on disk takes priority, and
whatever does not exist on disk still comes from the executable. The root (empty `Path`) falls
back to the embedded `index.html`. The `..` check keeps the page from reading files outside the
`web\` folder.

## Errors and exceptions

The event is called from inside a WebView2 COM callback, and a Delphi exception escaping from
there would be a problem. So `TWebView2Browser` catches any exception from the event and answers
**500 Internal Server Error**, with the text `500 - <Class>: <Message>`:

```js
fetch('api/erro').then(r => r.text()).then(console.log);
// "500 - Exception: deliberate error in the Delphi handler"
```

The 500 is sent even if the request was not for the embedded host: after an exception, there is
no way to know whether the event intended to handle it.

Error responses (404, 500) for the **main page** make `OnNavigationCompleted` arrive with
`Success = False`. For `fetch` and XHR, the error shows up only in the response's `status`.

## Caveats and limitations

- **Runs on the UI thread.** The event is synchronous, and while it runs the VCL and the page
  are frozen. For slow work, use the [deferred response](#deferred-response).
- **Whole body in memory.** The response content is copied into an in-memory stream before
  being delivered. For large files (videos, downloads), prefer serving over the network or from
  disk with a `file://` URL.
- **CORS.** An intercepted response from another domain is still subject to CORS. If a page at
  `https://app.localhost` does a `fetch` to `https://api.example.com` and Delphi answers in its
  place, include `Response.SetHeader('Access-Control-Allow-Origin', 'https://app.localhost')`.
  Routes on the same host (`api/...`) do not have this problem.
- **One header per name.** `Response.SetHeader` replaces; there is no way to send the same
  header twice (e.g. several `Set-Cookie`).
- **Filters** can be removed (`RemoveWebResourceRequestedFilter`, with the same pattern and
  context) and counted (`ResourceFilterCount`), but not listed.

## Under the hood

For whoever is going to extend the code:

| Piece | Where | What it does |
|---|---|---|
| `AddWebResourceRequestedFilter` | `WebView2Browser.pas` | Stores the filter and calls `ApplyResourceFilters` |
| `ApplyResourceFilters` | `WebView2Browser.pas` | Registers the handler with WebView2 (once) and applies the pending filters. Also called in `ControllerCreated` |
| `WebResourceRequested` | `WebView2Browser.pas` | Creates `Request`/`Response`, fires the event, falls back to `ServeEmbedded` and handles exceptions |
| `SendResponse` | `WebView2Browser.pas` | Copies the content into an `IStream` (`SHCreateMemStream`) and calls `CreateWebResourceResponse` and `put_Response` |
| `ICoreWebView2WebResourceRequest`, `...Response`, `...RequestedEventArgs`, `ICoreWebView2HttpRequestHeaders` | `WebView2.pas` | COM interfaces, in the vtable order of `WebView2.h` |

Two Delphi 7 details that show up here:

- `SHCreateMemStream` is declared returning `Pointer`, not `IStream`. Delphi treats interfaces
  returned by a function as a hidden parameter, which does not match the C convention. The
  pointer is assigned "raw" (`Pointer(Result) := ...`) to take over the reference without an
  extra `AddRef`.
- The `IStream` created copies the bytes. Once sent, the response depends neither on the
  `TMemoryStream` nor on the `RCDATA` resource, so both can be freed at the end of the event.
