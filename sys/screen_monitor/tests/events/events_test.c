#include "../../native_stub.h"
#include <string.h>

/* Exercise the production queue without requiring physical display hot-plug. */
int32_t proton_test_screen_event_snapshots(void) {
  screen_monitor_state_t state = {0};
  screen_monitor_lock_init(&state);
  screen_monitor_display_t secondary = {0};
  secondary.id = 42;
  secondary.x = 1920;
  secondary.width = 1280;
  secondary.present = 1;
  screen_monitor_push_event(&state, screen_monitor_EVENT_REMOVED, &secondary);
  secondary.id = 43;
  secondary.width = 2560;
  screen_monitor_push_event(&state, screen_monitor_EVENT_ADDED, &secondary);
  secondary.width = 3840;
  screen_monitor_push_event(&state, screen_monitor_EVENT_METRICS_CHANGED, &secondary);
  memset(&secondary, 0, sizeof(secondary));
  /* No current primary display is available when the events are consumed. */
  state.display_count = 0;
  int32_t kind = -1;
  screen_monitor_display_t display = {0};
  int32_t valid =
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK &&
      kind == screen_monitor_EVENT_REMOVED && display.id == 42 && display.width == 1280;
  valid = valid &&
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK &&
      kind == screen_monitor_EVENT_ADDED && display.id == 43 && display.width == 2560;
  valid = valid &&
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK &&
      kind == screen_monitor_EVENT_METRICS_CHANGED && display.id == 43 && display.width == 3840;
  valid = valid &&
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_EMPTY;
  screen_monitor_release_events(&state);
  screen_monitor_lock_destroy(&state);
  return valid;
}
