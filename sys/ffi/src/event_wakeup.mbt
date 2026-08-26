///|
/// An opaque native callback that wakes an embedding host event loop.
///
/// MoonBit code may only pass this token back to a native event producer. It
/// cannot invoke or wrap the callback, which keeps foreign threads out of the
/// MoonBit runtime.
#external
pub type EventWakeup
