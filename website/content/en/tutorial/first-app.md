# Create a project

[中文](../zh/tutorial/first-app.html)

This guide creates a desktop window with the minimal template. You will run it, change its contents, and build the executable. Finish [prerequisites](../installation.md) before starting.

## 1. Create the application

Run this command in the directory where you keep projects, not inside another MoonBit workspace:

```sh
proton_cli new hello-proton --template minimal --yes
cd hello-proton
```

The explicit `--template minimal` matters: the non-interactive default is `isomorphic`. `--yes` accepts generated defaults. For a distributable application, choose your identity at creation with `--identifier com.example.hello-proton`.

The generated `app/main.mbt` owns the window and its HTML. `moon.mod` declares dependencies, `app/moon.pkg` imports packages, and `proton.project.json` identifies the application and its build entry.

## 2. Prepare and run

From `hello-proton/`:

```sh
moon update
proton_cli cef setup
proton_cli dev
```

A native window opens with the generated greeting. The terminal remains occupied while the app runs. Close the window before continuing.

The CLI builds the native executable and starts it with the configured project metadata. This template has inline HTML, so there is no frontend server to start.

## 3. Change the page

Replace the entire contents of **`app/main.mbt`** with:

```moonbit
///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Hello Proton</title>
    #|<style>
    #|  body { font: 18px system-ui; padding: 32px; }
    #|</style>
    #|<h1>Hello from MoonBit</h1>
    #|<p>This page lives inside a desktop window.</p>
    #|</html>
  @proton.html("Hello Proton", html, width=900, height=700)
  .load_config()
  .run_or_abort()
}
```

Run `proton_cli dev` again. You should see “Hello from MoonBit”, a short paragraph, and a 900 × 700 initial window.

`@proton.html` creates the app builder. Its first argument is the window title; the second is the HTML document. The `#|` lines form a MoonBit multiline string.

`.load_config()` loads the required application identity from the generated metadata. Keep this call. The display title alone is not an application identity.

`.run_or_abort()` runs until the app exits and reports startup/runtime failures. The entry is async, so retain the template's `moonbitlang/async` import.

## 4. Check and build

After closing the window:

```sh
moon check --target native
proton_cli build
```

A successful build creates the native executable; it does not yet assemble a distributable application. [Build and distribute](../packaging.md) explains that next step.

## Where to go next

Read [project structure](../project-structure.md) to understand the generated files. To add interaction to this page, follow [calling the backend](commands-events.md). To write the UI in MoonBit too, use the [complete isomorphic example](isomorphic.md).

If the app does not start, run `proton_cli doctor` and inspect the full terminal error. If it builds but shows the old page, stop the previous process and rerun `dev`; this template has no frontend hot-reload server.
