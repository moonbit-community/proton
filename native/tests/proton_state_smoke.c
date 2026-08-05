#include "../src/proton_state.h"

#include <stdio.h>
#include <string.h>

// proton_state.c references exactly these external symbols; stub them so the
// state layer is tested in isolation, without linking the proton library.
static int g_set_error_calls = 0;
static int32_t g_set_error_last_code = 0;
static int g_is_closed_calls = 0;

int32_t proton_set_error(int32_t code, const char *message) {
  (void)message;
  g_set_error_calls++;
  g_set_error_last_code = code;
  return code;
}

int32_t proton_set_engine_status(int32_t status, const char *engine_error) {
  (void)engine_error;
  return status;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  g_is_closed_calls++;
  return window == (proton_engine_window_t *)0x1 ? 1 : 0;
}

uint64_t proton_engine_window_bridge_revision(proton_engine_window_t *window) {
  (void)window;
  return 0;
}

int32_t proton_engine_view_poll_event_json(proton_engine_view_t *view,
                                           char *buffer,
                                           int32_t buffer_len,
                                           int32_t *out_required_len,
                                           char *error,
                                           size_t error_len) {
  (void)view;
  (void)buffer;
  (void)buffer_len;
  (void)error;
  (void)error_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return PROTON_EVENT_NONE;
}

int32_t proton_engine_window_get_state(
    proton_engine_window_t *window,
    proton_engine_window_state_t *out_state, char *error, size_t error_len) {
  (void)window;
  (void)error;
  (void)error_len;
  if (out_state != NULL) {
    memset(out_state, 0, sizeof(*out_state));
  }
  return PROTON_OK;
}

int32_t proton_engine_window_get_close_request(
    proton_engine_window_t *window, uint64_t *out_request_id,
    int32_t *out_pending, char *error, size_t error_len) {
  (void)window;
  (void)error;
  (void)error_len;
  if (out_request_id != NULL) {
    *out_request_id = 0;
  }
  if (out_pending != NULL) {
    *out_pending = 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_poll_browser_event_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  (void)window;
  (void)buffer;
  (void)buffer_len;
  (void)error;
  (void)error_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return PROTON_EVENT_NONE;
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  (void)window;
  (void)error;
  (void)error_len;
  return PROTON_OK;
}

static int fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  return 1;
}

static int expect_status(const char *label, int32_t actual, int32_t expected) {
  if (actual != expected) {
    fprintf(stderr, "%s: expected %d, got %d\n", label, expected, actual);
    return 1;
  }
  return 0;
}

static int expect_event_contains(const char *label,
                                 const char *payload,
                                 const char *needle) {
  if (strstr(payload, needle) == NULL) {
    fprintf(stderr, "%s: expected '%s' in '%s'\n", label, needle, payload);
    return 1;
  }
  return 0;
}

int main(void) {
  proton_runtime_id_t runtime = PROTON_INVALID_HANDLE;
  proton_runtime_slot_t *runtime_slot = NULL;
  if (expect_status("runtime_slot_create",
                    proton_runtime_slot_create(false, NULL, &runtime,
                                               &runtime_slot),
                    PROTON_OK)) {
    return 1;
  }

  // Window 0 reports engine-side closed; the 32nd create fills the event
  // queue exactly, so the first sync cannot deliver its window_closed.
  proton_window_id_t handles[32];
  proton_window_slot_t *slots[32];
  for (int i = 0; i < 32; i++) {
    handles[i] = PROTON_INVALID_HANDLE;
    slots[i] = NULL;
    proton_engine_window_t *engine_window = (proton_engine_window_t *)0x2;
    if (i == 0) {
      engine_window = (proton_engine_window_t *)0x1;
    }
    if (expect_status("window_slot_create",
                      proton_window_slot_create(runtime_slot, runtime,
                                                engine_window, 640, 480,
                                                &handles[i], &slots[i]),
                      PROTON_OK)) {
      return 1;
    }
  }
  if (expect_status("event queue full after 32 window_created",
                    (int32_t)runtime_slot->event_count, PROTON_MAX_EVENTS)) {
    return 1;
  }
  // window_slot_create initializes visible=false; mark the windows shown so
  // the sync's "visible stays true on a full queue" assertion is meaningful.
  for (int i = 0; i < 32; i++) {
    slots[i]->visible = true;
  }

  proton_runtime_sync_engine_closed_windows(runtime, runtime_slot);
  if (expect_status("sync scans every engine window with a full queue",
                    g_is_closed_calls, 32) ||
      expect_status("failed enqueue reports the queue error",
                    g_set_error_calls, 1) ||
      expect_status("failed enqueue uses PROTON_ERR_QUEUE_FAILED",
                    g_set_error_last_code, PROTON_ERR_QUEUE_FAILED) ||
      expect_status("full queue defers window_closed",
                    (int32_t)runtime_slot->event_count, PROTON_MAX_EVENTS)) {
    return 1;
  }
  for (int i = 0; i < 32; i++) {
    if (slots[i]->closed_event_sent) {
      return fail("closed_event_sent must stay false when the queue is full");
    }
    if (!slots[i]->visible) {
      return fail("visible must stay true when the queue is full");
    }
  }

  char buffer[512];
  int32_t required = 0;
  if (expect_status("poll drains one window_created",
                    proton_runtime_poll_event(runtime_slot, buffer,
                                              (int32_t)sizeof(buffer),
                                              &required),
                    PROTON_OK)) {
    return 1;
  }
  char expected_window[64];
  snprintf(expected_window, sizeof(expected_window), "\"window\":\"%lld\"",
           (long long)handles[0]);
  if (expect_event_contains("first drained event", buffer,
                            "\"type\":\"window_created\"") ||
      expect_event_contains("first drained event", buffer,
                            expected_window)) {
    return 1;
  }

  proton_runtime_sync_engine_closed_windows(runtime, runtime_slot);
  if (!slots[0]->closed_event_sent) {
    return fail("sync must enqueue window_closed once the queue has room");
  }
  if (slots[0]->visible) {
    return fail("sync must clear visible after queueing window_closed");
  }
  if (expect_status("window_closed refills the queue",
                    (int32_t)runtime_slot->event_count, PROTON_MAX_EVENTS)) {
    return 1;
  }

  int closed_events = 0;
  for (int i = 0; i < 32; i++) {
    required = 0;
    if (expect_status("poll drains queued event",
                      proton_runtime_poll_event(runtime_slot, buffer,
                                                (int32_t)sizeof(buffer),
                                                &required),
                      PROTON_OK)) {
      return 1;
    }
    if (strstr(buffer, "\"type\":\"window_closed\"") != NULL) {
      closed_events++;
      if (i != 31) {
        return fail("window_closed must arrive after the queued creates");
      }
      if (strstr(buffer, expected_window) == NULL) {
        return fail("window_closed must name the closed window");
      }
    }
  }
  if (closed_events != 1) {
    return fail("expected exactly one window_closed event");
  }
  required = -1;
  if (expect_status("poll reports the drained queue",
                    proton_runtime_poll_event(runtime_slot, buffer,
                                              (int32_t)sizeof(buffer),
                                              &required),
                    PROTON_EVENT_NONE)) {
    return 1;
  }
  if (required != 0) {
    return fail("drained queue should require zero bytes");
  }

  proton_runtime_sync_engine_closed_windows(runtime, runtime_slot);
  if (expect_status("closed window is not requeued",
                    (int32_t)runtime_slot->event_count, 0)) {
    return 1;
  }
  required = -1;
  if (expect_status("poll stays empty after resync",
                    proton_runtime_poll_event(runtime_slot, buffer,
                                              (int32_t)sizeof(buffer),
                                              &required),
                    PROTON_EVENT_NONE)) {
    return 1;
  }
  if (required != 0) {
    return fail("resync should leave the queue empty");
  }

  // View slots: views resolve against their owning window, are destroyed with
  // it, and recycle slots with a fresh generation.
  proton_view_id_t view = PROTON_INVALID_HANDLE;
  proton_view_slot_t *view_slot = NULL;
  if (expect_status("view_slot_create",
                    proton_view_slot_create(runtime, handles[1],
                                            (proton_engine_view_t *)0x3, 10,
                                            20, 320, 200, 1, true, &view,
                                            &view_slot),
                    PROTON_OK)) {
    return 1;
  }
  proton_view_slot_t *resolved = NULL;
  if (expect_status("proton_get_view resolves a live view",
                    proton_get_view(view, &resolved), PROTON_OK)) {
    return 1;
  }
  if (resolved != view_slot) {
    return fail("proton_get_view must return the created slot");
  }
  if (expect_status("view slot keeps x", view_slot->x, 10) ||
      expect_status("view slot keeps width", view_slot->width, 320) ||
      expect_status("view slot keeps z_order", view_slot->z_order, 1)) {
    return 1;
  }
  if (!view_slot->visible) {
    return fail("view slot must keep the visible flag");
  }
  proton_view_id_t second_view = PROTON_INVALID_HANDLE;
  if (expect_status("second view_slot_create",
                    proton_view_slot_create(runtime, handles[1],
                                            (proton_engine_view_t *)0x4, 0, 0,
                                            100, 100, 0, false, &second_view,
                                            NULL),
                    PROTON_OK)) {
    return 1;
  }
  proton_destroy_views_for_window(handles[1]);
  if (expect_status("destroyed view reports PROTON_ERR_DESTROYED",
                    proton_get_view(view, &resolved), PROTON_ERR_DESTROYED)) {
    return 1;
  }
  if (expect_status("sibling view is destroyed with the window",
                    proton_get_view(second_view, &resolved),
                    PROTON_ERR_DESTROYED)) {
    return 1;
  }
  if (expect_status("window handles are not view handles",
                    proton_get_view(handles[1], &resolved),
                    PROTON_ERR_INVALID_HANDLE)) {
    return 1;
  }
  if (expect_status("views on other windows stay live",
                    proton_view_slot_create(runtime, handles[2],
                                            (proton_engine_view_t *)0x5, 0, 0,
                                            50, 50, 0, true, &view, NULL),
                    PROTON_OK)) {
    return 1;
  }
  proton_view_id_t recycled = PROTON_INVALID_HANDLE;
  if (expect_status("recycled view slot is recreated",
                    proton_view_slot_create(runtime, handles[1],
                                            (proton_engine_view_t *)0x6, 0, 0,
                                            50, 50, 0, true, &recycled, NULL),
                    PROTON_OK)) {
    return 1;
  }
  if (recycled == second_view) {
    return fail("recycled view slot must bump its generation");
  }
  proton_destroy_views_for_window(handles[1]);
  proton_destroy_views_for_window(handles[2]);

  return 0;
}
