# Proton

This glossary defines the project-specific language used to describe Proton's
application bridge and frontend integrations.

## Bridge

**Bridge transport**:
The framework-neutral channel that carries request, response, and event JSON
text between frontend code and a Proton backend.
_Avoid_: Command framework, Rabbita bridge

**Bridge failure**:
A structured bridge rejection with a stable machine-readable code and a
human-readable message, mapped by the Proton client into a client failure.
_Avoid_: Result envelope, unstructured JavaScript error

**Caller cancellation**:
The current frontend task stopping its wait and releasing renderer-side pending
state without promising to stop or roll back backend command execution.
_Avoid_: Command rollback, backend cancellation

**Lifecycle cancellation**:
The owner-driven cancellation and joining of backend tasks before their window
or application lifecycle ends.
_Avoid_: Caller cancellation, forced process exit

**Proton client**:
The frontend MoonBit layer that owns typed request encoding and response or
event decoding over the bridge transport.
_Avoid_: Rabbita client, bridge adapter

**Current-page bridge**:
The single Proton bridge capability supplied by the active renderer context.
Frontend application code uses it as an environment capability rather than
constructing or passing client instances.
_Avoid_: Global client, backend connection

**JavaScript client**:
The supported object-oriented frontend surface exposed to ordinary JavaScript
code over the same bridge transport as the Proton client.
_Avoid_: Compatibility bridge, separate protocol

**Frontend toolchain**:
The external web build and development workflow coordinated by Proton CLI but
owned by the selected frontend framework tooling, such as Warren for Rabbita.
_Avoid_: Proton renderer, native build

**Proton Rabbita adapter**:
The Rabbita integration layer that maps typed Proton client operations to
Rabbita commands and bridge events to Rabbita subscriptions without owning
serialization.
_Avoid_: Codec, transport

**Proton command effect**:
A Rabbita-managed command that executes one asynchronous Proton client
invocation and returns its completion to the Rabbita message flow.
_Avoid_: Async client API, command handler

**Command completion**:
The two explicit Rabbita message paths produced by a Proton command effect:
one for a successful command outcome and one for a client failure.
_Avoid_: Result callback, optional failure handler

**Shared contract**:
The target-neutral collection of application request, response, and event
payload types together with their typed command and event descriptors.
_Avoid_: Backend API, frontend model

**Application contract**:
The application-wide set of typed commands and live events shared directly by
one GUI frontend and backend, with identities unique within that application.
_Avoid_: Service, extension namespace

**Command descriptor**:
A target-neutral value that binds one stable command identity to its request
and response types. It is the authoritative source of command identity.
_Avoid_: Handler, route

**Command binding**:
The backend association between one command descriptor and a handler whose
single request value and response value match that descriptor.
_Avoid_: Command definition, payload generation

**Backend instance**:
An application-scoped owner of mutable backend state that may receive command
bindings without becoming part of command identity.
_Avoid_: Service namespace, global backend state

**Application lifecycle**:
The outer lifetime that owns application-scoped backend resources and contains
every window lifecycle.
_Avoid_: Primary window lifetime, process-global state

**Window lifecycle**:
The lifetime of one application window and its window-scoped capabilities,
strictly contained within the application lifecycle.
_Avoid_: Application lifecycle, page navigation

**Typed command dispatch**:
The single asynchronous backend execution path used by every typed command
binding, regardless of whether its source handler is synchronous or async.
_Avoid_: Synchronous bridge command, dual dispatch

**Command registrar**:
The application startup capability used by generated backend code to bind
typed command descriptors directly to handlers.
_Avoid_: Command collection, extension installation

**Command context**:
The request-scoped backend capability supplied to a command handler for
window- or page-specific operations, typed event emission, and its command task
group.
_Avoid_: Request payload, global event sender

**Command outcome**:
The response value of a command, including expected business alternatives that
frontend code may handle explicitly.
_Avoid_: Remote exception, transport error

**Client failure**:
An encoding, bridge, timeout, remote execution, or decoding failure raised by
the Proton client rather than represented as a command outcome.
_Avoid_: Command outcome, backend error type

**Event descriptor**:
A target-neutral value that binds one stable event identity to its payload
type. It is the authoritative source of event identity.
_Avoid_: Event handler, subscription

**Event emission**:
The request-scoped publication of a typed event through a command context.
_Avoid_: Generated event helper, host-scoped event sender

**Window event emission**:
The publication of a typed background event to the active page of one
explicitly selected application window.
_Avoid_: Process-wide event broadcast, implicit current window

**Window event emitter**:
A retainable capability for window event emission that remains associated with
one application window.
_Avoid_: Global event sender, command context

**Window context**:
The lifecycle capability supplied when one application window becomes ready,
including its window event emitter and window task group.
_Avoid_: Command context, application singleton

**Lifecycle task group**:
The official MoonBit async task group owned by an application, window, or
command lifecycle and made directly available to backend code.
_Avoid_: Task wrapper, detached task

**Extension contract**:
The target-neutral command descriptors, event descriptors, and payload types
owned and scoped by one Proton extension independently of its native
implementation.
_Avoid_: Extension backend, core contract

**Extension metadata**:
The statically discoverable identity, package, platform, and dependency
information for one extension, excluding its command and event schemas.
_Avoid_: Extension contract, API manifest

**Contract route**:
The opaque application or extension scope carried by a command or event
descriptor without exposing its transport name.
_Avoid_: Wire prefix, user-assembled operation name

**Live event**:
A non-replayed notification delivered only while the current page has an
active subscription. Initial or recoverable state is obtained through a
command instead.
_Avoid_: Event log, state snapshot

**Subscription failure**:
An explicit Rabbita message path for subscription installation or event
decoding failures that does not terminate an otherwise active subscription.
_Avoid_: Dropped event, terminal subscription

## Code Generation

**Application binding generation**:
The conversion of application command annotations into typed registration
source owned by the annotated backend package.
_Avoid_: Manual registration maintenance, committed application bindings

**Published binding source**:
Generated source distributed as part of a framework or extension package.
_Avoid_: Consumer-time package generation, hidden release dependency

**Generated-source verification**:
The comparison of regenerated binding source with its distributed form.
_Avoid_: Build-time mutation, unchecked generated source

**Package command registrar**:
The typed registration entry point owned by one backend package for the command
bindings declared in that package.
_Avoid_: Module-wide command scan, implicit cross-package registration
