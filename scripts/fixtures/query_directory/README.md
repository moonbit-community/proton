# Internal query prototype: directory browser

The source scaffold smoke test installs this second frontend into its temporary
application. It imports the same generated `frontend/internal/query` package as
Todo; no query implementation is copied or specialized for directory browsing.
The backend lists real disposable directories prepared by the test. This fixture
is not part of the default scaffold or a published API.

The page has no version numbers or invalidation event. It exercises explicit
input changes, retained data with its original path, empty versus failed reads,
retry, and component destruction while a request is pending. Todo separately
exercises event invalidation and listener-before-query initialization.

The fixture also exposes a test-only command to focus its native host window.
The smoke test activates the window whose DOM it checks so native occlusion
cannot suspend the animation frames that render query state.
