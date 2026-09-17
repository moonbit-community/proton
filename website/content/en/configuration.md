# Configuring the frontend and assets

[中文](zh/configuration.html)

Proton can load inline HTML, a URL, a local file, or bundled assets. A separate frontend tool is optional. This guide explains the isomorphic template's working configuration and how its development and packaged entries fit together.

## The project configuration

The isomorphic template generates **`proton.project.json`** with this shape. Install Warren once before running the frontend commands:

```sh
moon install moonbit-community/warren@0.3.2
```

The configuration calls the installed `warren` executable:

```json
{
  "identifier": "com.example.todo-app",
  "backend": {
    "path": ".",
    "package": "backend/app"
  },
  "frontend": {
    "path": "frontend",
    "dev_url": "http://127.0.0.1:4300",
    "before_dev": "warren dev --browser-entry main --direct --port 4300",
    "before_build": "warren build --browser-entry main",
    "dist": "dist"
  },
  "package": {
    "product_name": "Todo App",
    "version": "0.1.0",
    "output": "dist"
  }
}
```

Keep the identifier you chose for your application. This configuration is for the isomorphic workspace; the minimal project instead builds its `app` package and has no `frontend` section.

## How development works

From the project root, `proton_cli dev`:

1. Runs `frontend.before_dev` from `frontend.path`.
2. Waits for `frontend.dev_url` to become available.
3. Builds `backend.package` from `backend.path` and starts the native app using that URL.

Keep the configured URL and the server port in agreement. The CLI rejects an already occupied endpoint when it is responsible for starting the server. If you run the frontend separately, use:

```sh
proton_cli dev --no-frontend
```

The frontend must already be reachable at the configured URL. An ordinary browser preview does not include the native bridge.

## How production assets work

The backend entry remains:

```moonbit
@proton.asset("Todo App", "frontend/dist/index.html")
```

This is the entry expression inside the template's existing builder chain, not a complete `main`.

`proton_cli build` runs `frontend.before_build`, checks `frontend.dist`, then builds the native backend. The frontend command runs inside `frontend.path`, so its `dist` resolves to `frontend/dist` in the project.

Do not replace the production asset entry with a hardcoded development URL. A packaged application must load its built files without your development server.

## Use a different frontend

Any frontend that produces HTML, CSS, and JavaScript can provide the web UI. Replace the frontend commands, URL, and output directory with those of your chosen tool, and update the backend asset path accordingly.

Proton's CLI does not supply your frontend framework's configuration. Ensure its production output works from the packaged asset location, including stylesheet, script, image, and client-side route URLs. Test the packaged application; a successful development server does not verify those paths.

## Bundle additional files

For files read by the backend, add resource paths inside the existing `package` object:

```json
{
  "resources": ["assets"]
}
```

This is a fragment to merge, not the full project file. Create `assets/` at the project root and place the files there. Packaging copies the declared resources. Backend code resolves `assets/...` relative to `@proton.resource_dir()` in both development and packaged execution.

Keep persistent, writable user data outside the installed application resources. Run `proton_cli package --dry-run` after changing metadata, and test the actual packaged output before distributing it.

## Identity and runtime configuration

`identifier` is stable identity; `product_name` is display text; `package.version` is your application's release version. These are distinct from Proton's dependency version.

Use `.load_config()` to consume managed metadata. An unmanaged application can use `.identifier(...)` instead. Window options, command bindings, and capabilities stay in the MoonBit builder, not this JSON.
