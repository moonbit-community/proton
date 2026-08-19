///|
pub(all) struct DisplayBounds {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DisplayBounds with Eq::{not_equal, equal}

///|
pub extend DisplayBounds with Debug::{to_repr}

///|
pub extend DisplayBounds with ToJson::{to_json}

///|
pub extend DisplayBounds with FromJson::{from_json}

///|
/// A display snapshot mirroring Electron's `Display` object: identity, bounds,
/// work area, scale factor, and whether it is the primary display.
pub(all) struct DisplayJSON {
  id : Int
  bounds : DisplayBounds
  work_area : DisplayBounds
  scale_factor : Double
  is_primary : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DisplayJSON with Eq::{not_equal, equal}

///|
pub extend DisplayJSON with Debug::{to_repr}

///|
pub extend DisplayJSON with ToJson::{to_json}

///|
pub extend DisplayJSON with FromJson::{from_json}

///|
/// Reply for `getAllDisplays`, mirroring Electron's `screen.getAllDisplays()`.
pub(all) struct DisplaysReply {
  displays : Array[DisplayJSON]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DisplaysReply with Eq::{not_equal, equal}

///|
pub extend DisplaysReply with Debug::{to_repr}

///|
pub extend DisplaysReply with ToJson::{to_json}

///|
pub extend DisplaysReply with FromJson::{from_json}

///|
/// Reply for `getPrimaryDisplay` and `getDisplayNearestPoint`, each of which
/// returns a single display.
pub(all) struct DisplayReply {
  display : DisplayJSON
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DisplayReply with Eq::{not_equal, equal}

///|
pub extend DisplayReply with Debug::{to_repr}

///|
pub extend DisplayReply with ToJson::{to_json}

///|
pub extend DisplayReply with FromJson::{from_json}

///|
/// A point in root (physical pixel) coordinates.
pub(all) struct PointJSON {
  x : Int
  y : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PointJSON with Eq::{not_equal, equal}

///|
pub extend PointJSON with Debug::{to_repr}

///|
pub extend PointJSON with ToJson::{to_json}

///|
pub extend PointJSON with FromJson::{from_json}

///|
/// Reply for `getCursorScreenPoint`, mirroring Electron's
/// `screen.getCursorScreenPoint()`.
pub(all) struct CursorPointReply {
  point : PointJSON
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend CursorPointReply with Eq::{not_equal, equal}

///|
pub extend CursorPointReply with Debug::{to_repr}

///|
pub extend CursorPointReply with ToJson::{to_json}

///|
pub extend CursorPointReply with FromJson::{from_json}

///|
/// Request for `getDisplayNearestPoint`, mirroring the point argument of
/// Electron's `screen.getDisplayNearestPoint(point)`.
pub(all) struct NearestPointRequest {
  x : Int
  y : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend NearestPointRequest with Eq::{not_equal, equal}

///|
pub extend NearestPointRequest with Debug::{to_repr}

///|
pub extend NearestPointRequest with ToJson::{to_json}

///|
pub extend NearestPointRequest with FromJson::{from_json}

///|
/// Reply for `drainEvents`: the number of topology events that were drained and
/// forwarded to this renderer.
pub(all) struct ScreenEventReply {
  count : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ScreenEventReply with Eq::{not_equal, equal}

///|
pub extend ScreenEventReply with Debug::{to_repr}

///|
pub extend ScreenEventReply with ToJson::{to_json}

///|
pub extend ScreenEventReply with FromJson::{from_json}

///|
pub let get_all_displays : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  DisplaysReply,
] = extension.command("getAllDisplays")

///|
pub let get_primary_display : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  DisplayReply,
] = extension.command("getPrimaryDisplay")

///|
pub let get_display_nearest_point : @proton_contract.Command[
  NearestPointRequest,
  DisplayReply,
] = extension.command("getDisplayNearestPoint")

///|
pub let get_cursor_point : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  CursorPointReply,
] = extension.command("getCursorScreenPoint")

///|
pub let drain_events : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  ScreenEventReply,
] = extension.command("drainEvents")

///|
/// Payload for display topology change events. Mirrors the `newDisplay`
/// argument of Electron's `screen.on('display-added' | ...)` handlers.
pub let display_added : @proton_contract.Event[DisplayJSON] = extension.event(
  "display-added",
)

///|
pub let display_removed : @proton_contract.Event[DisplayJSON] = extension.event(
  "display-removed",
)

///|
pub let display_metrics_changed : @proton_contract.Event[DisplayJSON] = extension.event(
  "display-metrics-changed",
)
