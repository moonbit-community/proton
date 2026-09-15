# Single-instance fault tests

Run after installing the workspace CEF SDK:

```sh
node --test proton/internal/native/ffi/tests/app_instance.test.mjs
```

The runner compiles the real `proton_app_instance.c` and starts independent
primary/secondary processes. Only the native event sink is replaced: the test
controls when the owner attaches and consumes events. Production uses a five
second forwarding deadline; this test build uses one second.

Coverage includes stalled application dispatch, normal acceptance, startup
buffering, stopping and detached owners, late confirmation isolation, and owner
death/reacquisition. POSIX also tests a partial socket message and a completely
suspended primary. Every child has bounded supervision and cleanup.

The complementary `moon -C e2e run test --target native -- --single-instance`
scenario exercises the public App API, real event dispatch, and CEF/helper
shutdown. It is also part of `--self-hosted`.
