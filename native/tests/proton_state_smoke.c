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

  return 0;
}
