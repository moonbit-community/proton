#if defined(_WIN32)

#include "win_internal.h"

#include "../../proton_event.h"
#include "../cef_common/message.h"

#include "include/capi/cef_frame_capi.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  UINT id;
  const proton_menu_item_t *item;
} proton_win_menu_binding_t;

typedef struct {
  proton_win_menu_binding_t *bindings;
  size_t binding_count;
  size_t binding_capacity;
  UINT next_id;
} proton_win_menu_builder_t;

// TODO: Implement application menu rendering and command events on Windows.
int32_t proton_engine_runtime_set_menu(
    proton_engine_runtime_t *runtime, const proton_menu_bar_t *menu_bar,
    char *error, size_t error_len) {
  (void)runtime;
  (void)menu_bar;
  proton_engine_set_message(error, error_len,
                            "native app menus are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

static int32_t proton_win_menu_append_binding(
    proton_win_menu_builder_t *builder, const proton_menu_item_t *item,
    UINT *out_id, char *error, size_t error_len) {
  if (builder == NULL || item == NULL || out_id == NULL) {
    proton_engine_set_message(error, error_len,
                              "menu binding arguments are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (builder->next_id == 0) {
    proton_engine_set_message(error, error_len,
                              "popup menu has too many actionable items");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (builder->binding_count == builder->binding_capacity) {
    size_t capacity = builder->binding_capacity == 0
                          ? 16
                          : builder->binding_capacity * 2;
    if (capacity < builder->binding_capacity ||
        capacity > SIZE_MAX / sizeof(*builder->bindings)) {
      proton_engine_set_message(error, error_len,
                                "popup menu binding capacity overflowed");
      return PROTON_ERR_ENGINE;
    }
    proton_win_menu_binding_t *bindings =
        (proton_win_menu_binding_t *)realloc(
            builder->bindings, capacity * sizeof(*bindings));
    if (bindings == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to allocate popup menu bindings");
      return PROTON_ERR_ENGINE;
    }
    builder->bindings = bindings;
    builder->binding_capacity = capacity;
  }
  *out_id = builder->next_id++;
  builder->bindings[builder->binding_count++] =
      (proton_win_menu_binding_t){.id = *out_id, .item = item};
  return PROTON_OK;
}

static int32_t proton_win_menu_wide_text(
    const char *value, wchar_t **out_text, char *error, size_t error_len) {
  if (value == NULL || value[0] == '\0' || out_text == NULL) {
    proton_engine_set_message(error, error_len,
                              "popup menu label is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_text = NULL;
  int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
  if (length <= 0) {
    proton_engine_set_message(error, error_len,
                              "popup menu label is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  wchar_t *text = (wchar_t *)calloc((size_t)length, sizeof(*text));
  if (text == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate popup menu label");
    return PROTON_ERR_ENGINE;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, text,
                          length) <= 0) {
    free(text);
    proton_engine_set_message(error, error_len,
                              "popup menu label is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_text = text;
  return PROTON_OK;
}

static int32_t proton_win_menu_append_definition(
    HMENU menu, const proton_menu_t *definition,
    proton_win_menu_builder_t *builder, char *error, size_t error_len) {
  if (menu == NULL || definition == NULL || builder == NULL) {
    proton_engine_set_message(error, error_len,
                              "popup menu definition is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  for (size_t index = 0; index < definition->item_count; index++) {
    const proton_menu_item_t *item = &definition->items[index];
    if (item->kind == PROTON_MENU_ITEM_SEPARATOR) {
      if (!AppendMenuW(menu, MF_SEPARATOR, 0, NULL)) {
        proton_engine_set_message(error, error_len,
                                  "failed to append popup separator");
        return PROTON_ERR_PLATFORM;
      }
      continue;
    }
    if (item->kind == PROTON_MENU_ITEM_SUBMENU) {
      if (item->submenu == NULL || item->label == NULL ||
          item->label[0] == '\0') {
        proton_engine_set_message(error, error_len,
                                  "popup submenu requires a label");
        return PROTON_ERR_INVALID_ARGUMENT;
      }
      HMENU submenu = CreatePopupMenu();
      if (submenu == NULL) {
        proton_engine_set_message(error, error_len,
                                  "failed to create popup submenu");
        return PROTON_ERR_PLATFORM;
      }
      wchar_t *label = NULL;
      int32_t status = proton_win_menu_wide_text(
          item->label, &label, error, error_len);
      if (status == PROTON_OK) {
        status = proton_win_menu_append_definition(
            submenu, item->submenu, builder, error, error_len);
      }
      if (status == PROTON_OK &&
          !AppendMenuW(menu, MF_STRING | MF_POPUP, (UINT_PTR)submenu,
                       label)) {
        proton_engine_set_message(error, error_len,
                                  "failed to append popup submenu");
        status = PROTON_ERR_PLATFORM;
      }
      free(label);
      if (status != PROTON_OK) {
        DestroyMenu(submenu);
        return status;
      }
      continue;
    }
    if (item->kind != PROTON_MENU_ITEM_COMMAND &&
        item->kind != PROTON_MENU_ITEM_ROLE) {
      proton_engine_set_message(error, error_len,
                                "popup menu item kind is unsupported");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
    const char *value = item->kind == PROTON_MENU_ITEM_COMMAND ? item->id
                                                                : item->role;
    if (value == NULL || value[0] == '\0' || item->label == NULL ||
        item->label[0] == '\0') {
      proton_engine_set_message(error, error_len,
                                "popup action requires a value and label");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
    UINT id = 0;
    int32_t status = proton_win_menu_append_binding(
        builder, item, &id, error, error_len);
    wchar_t *label = NULL;
    if (status == PROTON_OK) {
      status = proton_win_menu_wide_text(
          item->label, &label, error, error_len);
    }
    if (status == PROTON_OK && !AppendMenuW(menu, MF_STRING, id, label)) {
      proton_engine_set_message(error, error_len,
                                "failed to append popup action");
      status = PROTON_ERR_PLATFORM;
    }
    free(label);
    if (status != PROTON_OK) {
      return status;
    }
  }
  return PROTON_OK;
}

static void proton_win_menu_apply_edit_role(proton_engine_window_t *window,
                                             const char *role) {
  if (window == NULL || window->browser == NULL || role == NULL) {
    return;
  }
  cef_frame_t *frame =
      window->browser->get_focused_frame != NULL
          ? window->browser->get_focused_frame(window->browser)
          : NULL;
  if (frame == NULL) {
    frame = window->browser->get_main_frame(window->browser);
  }
  if (frame == NULL) {
    return;
  }
  if (strcmp(role, "undo") == 0) {
    frame->undo(frame);
  } else if (strcmp(role, "redo") == 0) {
    frame->redo(frame);
  } else if (strcmp(role, "cut") == 0) {
    frame->cut(frame);
  } else if (strcmp(role, "copy") == 0) {
    frame->copy(frame);
  } else if (strcmp(role, "paste") == 0) {
    frame->paste(frame);
  } else if (strcmp(role, "select_all") == 0) {
    frame->select_all(frame);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void proton_win_menu_publish_quit(void) {
  proton_event_t *event = proton_event_create(PROTON_EVENT_QUIT_REQUESTED);
  if (event != NULL) {
    (void)proton_event_publish(event);
  }
}

static void proton_win_menu_apply_role(proton_engine_window_t *window,
                                        const char *role) {
  if (window == NULL || window->hwnd == NULL || role == NULL) {
    return;
  }
  if (strcmp(role, "quit") == 0) {
    proton_win_menu_publish_quit();
  } else if (strcmp(role, "hide") == 0) {
    ShowWindow(window->hwnd, SW_HIDE);
  } else if (strcmp(role, "hide_others") == 0) {
    for (proton_engine_window_t *candidate = proton_engine_windows_head();
         candidate != NULL; candidate = candidate->next) {
      if (candidate != window && candidate->runtime == window->runtime &&
          candidate->hwnd != NULL) {
        ShowWindow(candidate->hwnd, SW_HIDE);
      }
    }
  } else if (strcmp(role, "show_all") == 0) {
    for (proton_engine_window_t *candidate = proton_engine_windows_head();
         candidate != NULL; candidate = candidate->next) {
      if (candidate->runtime == window->runtime && candidate->hwnd != NULL) {
        ShowWindow(candidate->hwnd, SW_SHOW);
      }
    }
  } else if (strcmp(role, "close") == 0) {
    PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
  } else if (strcmp(role, "minimize") == 0) {
    ShowWindow(window->hwnd, SW_MINIMIZE);
  } else if (strcmp(role, "zoom") == 0) {
    ShowWindow(window->hwnd,
               IsZoomed(window->hwnd) ? SW_RESTORE : SW_MAXIMIZE);
  } else {
    proton_win_menu_apply_edit_role(window, role);
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
}

static void proton_win_menu_dispatch(
    proton_engine_window_t *window,
    const proton_win_menu_builder_t *builder, UINT selected_id) {
  if (window == NULL || builder == NULL || selected_id == 0) {
    return;
  }
  for (size_t index = 0; index < builder->binding_count; index++) {
    const proton_menu_item_t *item = builder->bindings[index].item;
    if (builder->bindings[index].id != selected_id || item == NULL) {
      continue;
    }
    if (item->kind == PROTON_MENU_ITEM_COMMAND) {
      proton_event_t *event = proton_event_create(PROTON_EVENT_MENU_COMMAND);
      if (event != NULL && proton_event_set_text(&event->text_a, item->id)) {
        event->window = window->public_window_id;
        (void)proton_event_publish(event);
      } else {
        proton_event_destroy(event);
      }
    } else if (item->kind == PROTON_MENU_ITEM_ROLE) {
      proton_win_menu_apply_role(window, item->role);
    }
    return;
  }
}

int32_t proton_engine_window_popup_menu(
    proton_engine_window_t *window, int32_t x, int32_t y,
    const proton_menu_bar_t *menu_bar, char *error, size_t error_len) {
  if (window == NULL || !proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "popup menus are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (menu_bar == NULL || menu_bar->menu_count == 0) {
    proton_engine_set_message(error, error_len,
                              "popup menu requires at least one menu");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->hwnd == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for a popup menu");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  HMENU popup = CreatePopupMenu();
  if (popup == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create popup menu");
    return PROTON_ERR_PLATFORM;
  }
  proton_win_menu_builder_t builder = {.next_id = 1};
  int32_t status = proton_win_menu_append_definition(
      popup, &menu_bar->menus[0], &builder, error, error_len);
  if (status != PROTON_OK) {
    DestroyMenu(popup);
    free(builder.bindings);
    return status;
  }

  UINT dpi = GetDpiForWindow(window->hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  /* Menu.popup receives renderer CSS pixels; Win32 popup coordinates are
     physical client pixels on a per-monitor-DPI-aware window. */
  POINT point = {
      .x = MulDiv(x, (int)dpi, USER_DEFAULT_SCREEN_DPI),
      .y = MulDiv(y, (int)dpi, USER_DEFAULT_SCREEN_DPI),
  };
  if (!ClientToScreen(window->hwnd, &point)) {
    DestroyMenu(popup);
    free(builder.bindings);
    proton_engine_set_message(error, error_len,
                              "failed to translate popup coordinates");
    return PROTON_ERR_PLATFORM;
  }
  SetForegroundWindow(window->hwnd);
  UINT selected_id = TrackPopupMenuEx(
      popup, TPM_LEFTALIGN | TPM_TOPALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD |
          TPM_NONOTIFY | TPM_WORKAREA,
      point.x, point.y, window->hwnd, NULL);
  PostMessageW(window->hwnd, WM_NULL, 0, 0);
  proton_win_menu_dispatch(window, &builder, selected_id);
  DestroyMenu(popup);
  free(builder.bindings);
  return PROTON_OK;
}

#endif
