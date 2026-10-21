# Proton Net Extension

The `net` extension provides a typed host-side HTTP request capability for
renderer code. It mirrors Electron's `net` responsibility boundary: network
requests run in the host process, while the renderer receives a structured
response through the Proton command bridge.

Grant the capability to a selected renderer target:

```moonbit
let app = @proton
  .html("Network", html)
  ..capability(@proton_ext_net.capability())
```

The generated renderer proxy accepts an HTTP method, an absolute `http://` or
`https://` URL, optional headers, and an optional UTF-8 body. It returns the
numeric status, status text, response headers, and a UTF-8-decoded response
body. Binary response bodies are decoded with replacement characters.

Only the explicitly granted renderer targets can invoke the capability. The
extension does not expose raw sockets or native handles, and it does not
follow redirects or maintain a cookie jar on behalf of the renderer.

The implementation supports `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`,
and `OPTIONS`. Unsupported methods and non-HTTP URLs are rejected before a
network request is started.

## Host-side file downloads

MoonBit backend code can call `download` directly. Import
`moonbit-community/proton_ext/net` as `@net`:

```moonbit
@net.download(
  url,
  destination,
  headers={ "Authorization": "Bearer \{token}" },
)
```

`download(url, destination, headers?, overwrite?, on_progress?)` streams a
complete HTTP(S) GET response to disk and returns `Unit` when the destination
has been saved. It raises `DownloadError` on failure. It does not read the
whole file into memory or convert binary data to text. Request headers apply
only to this call; browser cookies, proxy configuration, download handlers and
download events are not used.

Only HTTP 200 is accepted. Redirects, partial responses and other HTTP statuses
raise `HttpStatus(status~)`; a `Range` request header is rejected. Servers that
redirect to a download URL require the application to resolve that URL before
calling this function. There is no automatic retry, resume or file size limit.
Downloads temporarily default to `Accept-Encoding: identity` and reject any
response whose `Content-Encoding` is not identity, including when custom request
headers explicitly ask for compression. This avoids silently saving compressed
bytes while [async#672](https://github.com/moonbitlang/async/issues/672) remains
unfixed. Servers must provide an unencoded response for this function to succeed;
compressed responses raise `NetworkFailed` before any file is created.

`destination` is a complete file path, relative to the process working directory
or absolute. Its parent directory must already exist. The function does not
choose filenames from response headers or open a save dialog. Existing entries
are not replaced unless `overwrite=true`. A symbolic link at the destination
is an existing entry: explicit overwrite replaces the link itself, not its
target.

Data is written to an exclusively created sibling temporary file with owner-only
permissions on Unix. After the stream and file synchronization succeed, the
file is closed and moved to the destination. The final move enforces the
`overwrite` choice even when downloads compete for the same path. Replacing a
file installs a new file; it does not preserve the old file's permissions or
other metadata.

Failures and cancellation close resources and remove the temporary file,
preserving the existing destination until submission. Once the final move
starts it runs to completion without cancellation. A destination already
submitted is never removed by cancellation cleanup. Process crashes may leave
a temporary file; this function does not provide crash recovery or a power-loss
durability guarantee.

Optional progress uses a synchronous, non-raising observer:

```moonbit
@net.download(
  url,
  destination,
  headers={ "Authorization": "Bearer \{token}" },
  on_progress=progress => {
    update_progress(progress.received_bytes, progress.total_bytes)
  },
)
```

`DownloadProgress.received_bytes` counts bytes written to the temporary file.
`total_bytes` is `None` when the size cannot be determined, including chunked
and close-delimited responses. Notifications are coalesced;
keep the observer short. The final byte count is reported before file
submission, so reaching the total is not a success notification. Only normal
return confirms success.

Cancel the calling async task to cancel a download; use `@async.with_timeout`
when a deadline is needed. There is no independent download task registry.
`DownloadError` distinguishes invalid requests, HTTP statuses, existing
destinations, network failures and file failures. `CleanupFailed` retains the
primary error, if any, and the temporary path when cleanup itself fails.
Cancellation is not converted into an ordinary download error.

This function is **host-only**: it registers no renderer command and adds no
filesystem authority to `net.capability()`. For authenticated Cloud downloads,
an application command can obtain its token, authorize the requested file,
choose a destination and call `download`. The application decides whether to
forward progress to its frontend using existing events. Browser-managed
`WebContentsHandle.download_url` remains a separate operation.
