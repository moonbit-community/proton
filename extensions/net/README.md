# Proton Net Extension

The `net` extension provides a typed host-side HTTP request capability for
renderer code. It mirrors Electron's `net` responsibility boundary: network
requests run in the host process, while the renderer receives a structured
response through the Proton command bridge.

Grant the capability to a selected renderer target:

```moonbit
let app = @proton
  .html("Network", html)
  .capability(@proton_ext_net.capability())
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
