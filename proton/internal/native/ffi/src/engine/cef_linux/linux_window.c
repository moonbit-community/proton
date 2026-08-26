#if defined(__linux__)

#include "linux_internal.h"
#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../../proton_json.h"

#include "../cef_common/bridge_json.h"
#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"

#include <gtk/gtk.h>
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

#include <math.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void proton_engine_apply_size_constraints(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL || window->headless) {
    return;
  }
  GdkGeometry geometry = {0};
  GdkWindowHints hints = 0;
  if (window->min_width > 0) {
    geometry.min_width = window->min_width;
    geometry.min_height = window->min_height;
    hints = (GdkWindowHints)(hints | GDK_HINT_MIN_SIZE);
  }
  if (window->max_width > 0) {
    geometry.max_width = window->max_width;
    geometry.max_height = window->max_height;
    hints = (GdkWindowHints)(hints | GDK_HINT_MAX_SIZE);
  }
  gtk_window_set_geometry_hints(GTK_WINDOW(window->window), NULL,
                                hints == 0 ? NULL : &geometry, hints);
}

static gboolean proton_engine_on_window_delete(GtkWidget *widget,
                                               GdkEvent *event,
                                               gpointer user_data) {
  (void)widget;
  (void)event;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || window->closed) {
    return FALSE;
  }
  if (window->closing) {
    return FALSE;
  }
  if (window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return TRUE;
  }
  window->close_interception_bypass = 0;
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      int allow_close = 0;
      if (host->is_ready_to_be_closed != NULL &&
          host->is_ready_to_be_closed(host)) {
        allow_close = 1;
        window->closing = 1;
      } else if (host->try_close_browser != NULL) {
        allow_close = host->try_close_browser(host);
        if (allow_close) {
          window->closing = 1;
        }
      } else {
        host->close_browser(host, 0);
      }
      host->base.release((cef_base_ref_counted_t *)host);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
      return allow_close ? FALSE : TRUE;
    }
  }
  proton_engine_window_mark_closed(window);
  return FALSE;
}

static void proton_engine_on_window_destroy(GtkWidget *widget,
                                            gpointer user_data) {
  (void)widget;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL) {
    window->window = NULL;
    window->root_box = NULL;
    window->menu_bar = NULL;
    window->browser_host = NULL;
    window->overlay_controls = NULL;
    if (window->menu_accel_group != NULL) {
      g_object_unref(window->menu_accel_group);
      window->menu_accel_group = NULL;
    }
    proton_engine_overlay_release_input_windows(window);
  }
  if (window != NULL && !window->closed) {
    if (window->browser == NULL) {
      proton_engine_window_mark_closed(window);
    }
  }
}

void proton_engine_sync_browser_bounds(proton_engine_window_t *window) {
  if (window == NULL || window->browser == NULL) {
    return;
  }
  if (window->headless) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      if (host->was_resized != NULL) {
        host->was_resized(host);
      }
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return;
  }
  if (window->browser_host == NULL) {
    return;
  }
  GdkWindow *parent_gdk_window = gtk_widget_get_window(window->browser_host);
  if (parent_gdk_window == NULL) {
    return;
  }
  Display *display = GDK_WINDOW_XDISPLAY(parent_gdk_window);
  XWindowAttributes attributes;
  if (display == NULL ||
      !XGetWindowAttributes(display, GDK_WINDOW_XID(parent_gdk_window),
                            &attributes) ||
      attributes.width <= 0 || attributes.height <= 0) {
    return;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    return;
  }
  const cef_window_handle_t browser_handle = host->get_window_handle(host);
  if (browser_handle != 0) {
    GdkDisplay *gdk_display = gdk_window_get_display(parent_gdk_window);
    XWindowAttributes browser_attributes;
    gdk_x11_display_error_trap_push(gdk_display);
    const int browser_window_valid =
        XGetWindowAttributes(display, (Window)browser_handle,
                             &browser_attributes) != 0;
    if (browser_window_valid) {
      XMoveResizeWindow(display, (Window)browser_handle, 0, 0,
                        (unsigned int)attributes.width,
                        (unsigned int)attributes.height);
    }
    XSync(display, False);
    (void)gdk_x11_display_error_trap_pop(gdk_display);
  }
  if (host->was_resized != NULL) {
    host->was_resized(host);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  if (window->overlay_controls != NULL) {
    GdkWindow *controls_window =
        gtk_widget_get_window(window->overlay_controls);
    if (controls_window != NULL) {
      gdk_window_raise(controls_window);
    }
  }
}

static void proton_engine_browser_host_size_allocate(GtkWidget *widget,
                                                      GtkAllocation *allocation,
                                                      gpointer user_data) {
  (void)widget;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || allocation == NULL) {
    return;
  }
  window->width = allocation->width;
  window->height = allocation->height;
  proton_engine_overlay_update_input_shape(window);
  proton_engine_sync_browser_bounds(window);
}

static gboolean proton_engine_window_configure(GtkWidget *widget,
                                               GdkEventConfigure *event,
                                               gpointer user_data) {
  (void)widget;
  (void)event;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  proton_engine_sync_browser_bounds(window);
  if (window != NULL && window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      if (host->notify_move_or_resize_started != NULL) {
        host->notify_move_or_resize_started(host);
      }
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return FALSE;
}

static void proton_engine_window_state_notify(GObject *object,
                                              GParamSpec *parameter,
                                              gpointer user_data) {
  (void)object;
  (void)parameter;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_window_screen_changed(GtkWidget *widget,
                                                GdkScreen *previous,
                                                gpointer user_data) {
  (void)widget;
  (void)previous;
  proton_engine_window_state_notify(NULL, NULL, user_data);
}

static void proton_engine_window_style_updated(GtkWidget *widget,
                                               gpointer user_data) {
  (void)widget;
  proton_engine_window_state_notify(NULL, NULL, user_data);
}

static void proton_engine_use_default_x11_visual(GtkWidget *widget) {
  if (widget == NULL) {
    return;
  }
  GdkScreen *screen = gtk_widget_get_screen(widget);
  if (screen == NULL || !GDK_IS_X11_SCREEN(screen)) {
    return;
  }
  Display *display = GDK_SCREEN_XDISPLAY(screen);
  Visual *default_visual =
      DefaultVisual(display, GDK_SCREEN_XNUMBER(screen));
  if (default_visual == NULL) {
    return;
  }
  GList *visuals = gdk_screen_list_visuals(screen);
  for (GList *cursor = visuals; cursor != NULL; cursor = cursor->next) {
    GdkVisual *visual = GDK_VISUAL(cursor->data);
    Visual *xvisual = gdk_x11_visual_get_xvisual(visual);
    if (xvisual != NULL && xvisual->visualid == default_visual->visualid) {
      gtk_widget_set_visual(widget, visual);
      break;
    }
  }
  g_list_free(visuals);
}

int proton_engine_ensure_gtk(char *error, size_t error_len) {
  static int initialized = 0;
  static int available = 0;
  if (initialized) {
    if (!available) {
      proton_engine_set_message(error, error_len,
                                "GTK X11 initialization failed");
    }
    return available;
  }
  int argc = 0;
  char **argv = NULL;
  g_setenv("GDK_BACKEND", "x11", TRUE);
  gdk_set_allowed_backends("x11");
  available = gtk_init_check(&argc, &argv) ? 1 : 0;
  if (available) {
    GdkDisplay *display = gdk_display_get_default();
    if (display == NULL || !GDK_IS_X11_DISPLAY(display)) {
      available = 0;
    }
  }
  initialized = 1;
  if (!available) {
    proton_engine_set_message(error, error_len,
                              "GTK X11 initialization failed");
  }
  return available;
}

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len) {
  cef_window_info_t window_info;
  cef_browser_settings_t browser_settings;
  cef_string_t url = {0};
  memset(&window_info, 0, sizeof(window_info));
  memset(&browser_settings, 0, sizeof(browser_settings));
  window_info.size = sizeof(window_info);
  browser_settings.size = sizeof(browser_settings);
  if (window == NULL || window->client == NULL ||
      (!window->headless &&
       (window->browser_host == NULL ||
        gtk_widget_get_window(window->browser_host) == NULL))) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int browser_width = window->width;
  int browser_height = window->height;
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
    GdkWindow *top_gdk_window = gtk_widget_get_window(window->browser_host);
    window_info.parent_window =
        (cef_window_handle_t)GDK_WINDOW_XID(top_gdk_window);
    XWindowAttributes parent_attributes;
    memset(&parent_attributes, 0, sizeof(parent_attributes));
    Display *display = GDK_WINDOW_XDISPLAY(top_gdk_window);
    if (display != NULL) {
      (void)XGetWindowAttributes(
          display, GDK_WINDOW_XID(gtk_widget_get_window(window->browser_host)),
          &parent_attributes);
    }
    browser_width =
        parent_attributes.width > 0 ? parent_attributes.width : window->width;
    browser_height = parent_attributes.height > 0 ? parent_attributes.height
                                                  : window->height;
  }
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = browser_width;
  window_info.bounds.height = browser_height;
  proton_engine_set_string(&window_info.window_name, "Proton");
  proton_engine_set_string(&url,
                           initial_url != NULL && initial_url[0] != '\0'
                               ? initial_url
                               : "about:blank");

  cef_value_t *extra_info_value =
      proton_engine_bridge_renderer_extra_info_value(window->bridge_config_json);
  cef_dictionary_value_t *extra_info =
      extra_info_value != NULL
          ? extra_info_value->get_dictionary(extra_info_value)
          : NULL;
  window->browser = cef_browser_host_create_browser_sync(
      &window_info, &window->client->client, &url, &browser_settings,
      extra_info, NULL);
  if (extra_info_value != NULL) {
    extra_info_value->base.release((cef_base_ref_counted_t *)extra_info_value);
  }
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  window->browser_id = window->browser->get_identifier(window->browser);
  proton_engine_window_list_add(window);
  proton_engine_sync_browser_bounds(window);
  return PROTON_OK;
}

int32_t proton_engine_window_create(
    proton_engine_runtime_t *runtime,
    const proton_engine_window_config_t *input_config,
    proton_engine_window_t **out_window, char *error, size_t error_len) {
  if (out_window == NULL) {
    proton_engine_set_message(error, error_len, "out_window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_window = NULL;
  if (runtime == NULL || input_config == NULL ||
      !proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_window_config_t config = *input_config;
  int32_t status = PROTON_OK;
  if (runtime->headless && config.titlebar_overlay) {
    proton_engine_set_message(
        error, error_len,
        "titlebar overlay is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }

  proton_engine_window_t *window =
      (proton_engine_window_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate window state");
    return PROTON_ERR_ENGINE;
  }
  window->runtime = runtime;
  window->public_window_id = config.public_window;
  window->width = config.width;
  window->height = config.height;
  window->min_width = config.size_hint == 2 ? config.width : 0;
  window->min_height = config.size_hint == 2 ? config.height : 0;
  window->max_width = config.size_hint == 3 ? config.width : 0;
  window->max_height = config.size_hint == 3 ? config.height : 0;
  window->headless = runtime->headless;
  window->size_hint = config.size_hint;
  window->titlebar_overlay = config.titlebar_overlay;
  snprintf(window->titlebar_minimize_label,
           sizeof(window->titlebar_minimize_label), "%s",
           config.titlebar_minimize_label);
  snprintf(window->titlebar_maximize_label,
           sizeof(window->titlebar_maximize_label), "%s",
           config.titlebar_maximize_label);
  snprintf(window->titlebar_restore_label,
           sizeof(window->titlebar_restore_label), "%s",
           config.titlebar_restore_label);
  snprintf(window->titlebar_close_label,
           sizeof(window->titlebar_close_label), "%s",
           config.titlebar_close_label);
  window->zoom_percent = 100;
  window->bridge_config_json =
      config.bridge_config_json != NULL
          ? proton_engine_strdup(config.bridge_config_json)
          : NULL;
  window->max_bridge_payload_bytes = config.max_bridge_payload_bytes;
  window->browser_session = proton_browser_session_create(
      &config.browser_policy, proton_engine_browser_signal, NULL);
  if (window->browser_session == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser session");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_session_bind_window(window->browser_session,
                                     config.public_window);
  window->client = proton_engine_client_create(window);
  if (window->client == NULL) {
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  if (!window->headless) {
    window->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    if (window->window == NULL) {
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len, "window creation failed");
      return PROTON_ERR_PLATFORM;
    }
    window->root_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    if (window->root_box == NULL) {
      gtk_widget_destroy(window->window);
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len,
                                "window root container creation failed");
      return PROTON_ERR_PLATFORM;
    }
    proton_engine_use_default_x11_visual(window->window);
    gtk_window_set_title(GTK_WINDOW(window->window),
                         config.title[0] != '\0' ? config.title : "Proton");
    gtk_window_set_default_size(GTK_WINDOW(window->window), config.width,
                                config.height);
    if (config.size_hint == 1) {
      gtk_window_set_resizable(GTK_WINDOW(window->window), FALSE);
    }
    proton_engine_apply_size_constraints(window);
    if (window->titlebar_overlay) {
      gtk_window_set_decorated(GTK_WINDOW(window->window), FALSE);
      window->overlay = gtk_overlay_new();
      if (window->overlay == NULL) {
        gtk_widget_destroy(window->window);
        free(window->client);
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
        free(window);
        proton_engine_set_message(error, error_len,
                                  "overlay container creation failed");
        return PROTON_ERR_PLATFORM;
      }
    }
    window->browser_host = gtk_drawing_area_new();
    if (window->browser_host == NULL) {
      gtk_widget_destroy(window->window);
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len,
                                "browser host widget creation failed");
      return PROTON_ERR_PLATFORM;
    }
    proton_engine_use_default_x11_visual(window->browser_host);
    if (window->titlebar_overlay) {
      gtk_container_add(GTK_CONTAINER(window->overlay), window->browser_host);
      if (!proton_engine_overlay_create_controls(window)) {
        gtk_widget_destroy(window->window);
        free(window->client);
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
        free(window);
        proton_engine_set_message(error, error_len,
                                  "overlay window controls creation failed");
        return PROTON_ERR_PLATFORM;
      }
      gtk_box_pack_end(GTK_BOX(window->root_box), window->overlay, TRUE, TRUE,
                       0);
    } else {
      gtk_box_pack_end(GTK_BOX(window->root_box), window->browser_host, TRUE,
                       TRUE, 0);
    }
    gtk_container_add(GTK_CONTAINER(window->window), window->root_box);
    if (runtime->menu_definition != NULL) {
      status = proton_engine_window_install_menu(
          window, runtime->menu_definition, error, error_len);
      if (status != PROTON_OK) {
        gtk_widget_destroy(window->window);
        free(window->client);
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
        free(window);
        return status;
      }
    }
    g_signal_connect(window->window, "delete-event",
                     G_CALLBACK(proton_engine_on_window_delete), window);
    g_signal_connect(window->window, "destroy",
                     G_CALLBACK(proton_engine_on_window_destroy), window);
    g_signal_connect(window->window, "configure-event",
                     G_CALLBACK(proton_engine_window_configure), window);
    g_signal_connect(window->window, "notify::is-active",
                     G_CALLBACK(proton_engine_window_state_notify), window);
    g_signal_connect(window->window, "notify::scale-factor",
                     G_CALLBACK(proton_engine_window_state_notify), window);
    g_signal_connect(window->window, "screen-changed",
                     G_CALLBACK(proton_engine_window_screen_changed), window);
    g_signal_connect(window->window, "style-updated",
                     G_CALLBACK(proton_engine_window_style_updated), window);
    g_signal_connect(window->browser_host, "size-allocate",
                     G_CALLBACK(proton_engine_browser_host_size_allocate),
                     window);
    if (window->titlebar_overlay) {
      g_signal_connect(window->window, "window-state-event",
                       G_CALLBACK(proton_engine_overlay_window_state), window);
    }
    gtk_widget_realize(window->window);
    gtk_widget_realize(window->browser_host);
    gtk_widget_show_all(window->window);
    if (window->titlebar_overlay) {
      proton_engine_overlay_update_maximize_button(window);
      proton_engine_overlay_update_input_shape(window);
      const int resize_handle = proton_engine_overlay_resize_handle(window);
    }
  }

  status = proton_engine_window_create_browser(window, config.initial_url, error,
                                               error_len);
  if (status != PROTON_OK) {
    if (window->window != NULL) {
      gtk_widget_destroy(window->window);
    }
    free(window->client);
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    return status;
  }
  *out_window = window;
  return PROTON_OK;
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_dialog_cancel_window(window);
  if (window->closed && window->browser == NULL) {
    window->destroy_requested = 1;
    proton_engine_window_close_views(window);
    if (window->window != NULL) {
      g_signal_handlers_disconnect_by_data(window->window, window);
      gtk_widget_destroy(window->window);
      window->window = NULL;
      window->browser_host = NULL;
    }
    proton_engine_window_finalize_if_ready(window);
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
    window->destroy_requested = 1;
    window->closing = 1;
    proton_engine_window_close_views(window);
    host->close_browser(host, 1);
    host->base.release((cef_base_ref_counted_t *)host);
    return PROTON_OK;
  }
  window->closed = 1;
  window->destroy_requested = 1;
  proton_engine_window_close_views(window);
  if (window->window != NULL) {
    g_signal_handlers_disconnect_by_data(window->window, window);
    gtk_widget_destroy(window->window);
    window->window = NULL;
    window->browser_host = NULL;
  }
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->headless_hidden = 0;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_hidden(host, 0);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    gtk_widget_show_all(window->window);
    gtk_window_present(GTK_WINDOW(window->window));
  }
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->headless_hidden = 1;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_hidden(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    gtk_widget_hide(window->window);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless && window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
  }
  window->close_interception_bypass = 0;
  if (!window->headless) {
    gtk_window_close(GTK_WINDOW(window->window));
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    host->close_browser(host, 0);
    host->base.release((cef_base_ref_counted_t *)host);
  } else {
    proton_engine_window_mark_closed(window);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!window->headless) {
    gtk_window_present(GTK_WINDOW(window->window));
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->set_focus(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window title is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  gtk_window_set_title(GTK_WINDOW(window->window), title != NULL ? title : "");
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->width = width;
  window->height = height;
  if (window->headless) {
    proton_engine_sync_browser_bounds(window);
  } else {
    gtk_window_resize(GTK_WINDOW(window->window), width, height);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_minimum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window size constraints are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (width > 0 && window->max_width > 0 &&
      (width > window->max_width || height > window->max_height)) {
    proton_engine_set_message(error, error_len,
                              "minimum size exceeds maximum size");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->min_width = width;
  window->min_height = height;
  proton_engine_apply_size_constraints(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_maximum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window size constraints are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (width > 0 && window->min_width > 0 &&
      (width < window->min_width || height < window->min_height)) {
    proton_engine_set_message(error, error_len,
                              "maximum size is below minimum size");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->max_width = width;
  window->max_height = height;
  proton_engine_apply_size_constraints(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_movable(proton_engine_window_t *window,
                                         int32_t movable, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (movable != 0 && movable != 1) {
    proton_engine_set_message(error, error_len,
                              "movable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window movement is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron's Linux backend intentionally treats setMovable as a no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_opacity(proton_engine_window_t *window,
                                         double opacity, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (isnan(opacity)) {
    proton_engine_set_message(error, error_len,
                              "opacity must not be NaN");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window opacity is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  const double bounded_opacity = opacity < 0.0 ? 0.0 : (opacity > 1.0 ? 1.0 : opacity);
  gtk_widget_set_opacity(window->window, bounded_opacity);
  return PROTON_OK;
}

int32_t proton_engine_window_set_skip_taskbar(proton_engine_window_t *window,
                                              int32_t skip, char *error,
                                              size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (skip != 0 && skip != 1) {
    proton_engine_set_message(error, error_len, "skip must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "taskbar visibility is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron's Linux implementation intentionally treats setSkipTaskbar as
  // a successful no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_progress_bar(
    proton_engine_window_t *window, double progress, char *error,
    size_t error_len) {
  (void)progress;
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_set_message(
      error, error_len,
      "window progress is not implemented on Linux");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_window_flash_frame(
    proton_engine_window_t *window, int32_t flash, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (flash != 0 && flash != 1) {
    proton_engine_set_message(error, error_len, "flash must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window attention is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  gtk_window_set_urgency_hint(GTK_WINDOW(window->window), flash != 0);
  return PROTON_OK;
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {
  if (window == NULL || action == NULL ||
      (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len,
                              "window and action are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (action->kind == PROTON_ENGINE_WINDOW_SET_ZOOM_PERCENT) {
    if (window->browser == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser is not initialized");
      return PROTON_ERR_NOT_INITIALIZED;
    }
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available");
      return PROTON_ERR_ENGINE;
    }
    const double factor = (double)action->value / 100.0;
    host->set_zoom_level(host, log(factor) / log(1.2));
    host->base.release((cef_base_ref_counted_t *)host);
    window->zoom_percent = action->value;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "native window operation is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  switch (action->kind) {
  case PROTON_ENGINE_WINDOW_MINIMIZE:
    gtk_window_iconify(GTK_WINDOW(window->window));
    break;
  case PROTON_ENGINE_WINDOW_MAXIMIZE:
    gtk_window_maximize(GTK_WINDOW(window->window));
    break;
  case PROTON_ENGINE_WINDOW_RESTORE:
    gtk_window_unfullscreen(GTK_WINDOW(window->window));
    gtk_window_unmaximize(GTK_WINDOW(window->window));
    gtk_window_deiconify(GTK_WINDOW(window->window));
    break;
  case PROTON_ENGINE_WINDOW_SET_FULLSCREEN:
    if (action->value != 0) {
      gtk_window_fullscreen(GTK_WINDOW(window->window));
    } else {
      gtk_window_unfullscreen(GTK_WINDOW(window->window));
    }
    break;
  case PROTON_ENGINE_WINDOW_SET_POSITION:
    gtk_window_move(GTK_WINDOW(window->window), action->x, action->y);
    break;
  case PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP:
    gtk_window_set_keep_above(GTK_WINDOW(window->window),
                              action->value != 0);
    window->always_on_top = action->value != 0;
    break;
  case PROTON_ENGINE_WINDOW_SET_RESIZABLE:
    gtk_window_set_resizable(GTK_WINDOW(window->window), action->value != 0);
    break;
  default:
    proton_engine_set_message(error, error_len, "unknown window action");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_get_state(
    proton_engine_window_t *window,
    proton_engine_window_state_t *out_state,
    char *error,
    size_t error_len) {
  if (window == NULL || out_state == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and out_state are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  memset(out_state, 0, sizeof(*out_state));
  out_state->zoom_percent =
      window->zoom_percent > 0 ? window->zoom_percent : 100;
  out_state->scale_factor_percent = 100;
  if (window->headless) {
    out_state->width = window->width;
    out_state->height = window->height;
    out_state->visible = !window->headless_hidden;
    return PROTON_OK;
  }
  if (window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  gtk_window_get_position(GTK_WINDOW(window->window), &out_state->x,
                          &out_state->y);
  gtk_window_get_size(GTK_WINDOW(window->window), &out_state->width,
                      &out_state->height);
  GdkWindow *gdk_window = gtk_widget_get_window(window->window);
  if (gdk_window != NULL) {
    GdkDisplay *display = gdk_window_get_display(gdk_window);
    GdkMonitor *monitor =
        gdk_display_get_monitor_at_window(display, gdk_window);
    if (monitor != NULL) {
      GdkRectangle geometry = {0};
      GdkRectangle work = {0};
      gdk_monitor_get_geometry(monitor, &geometry);
      gdk_monitor_get_workarea(monitor, &work);
      out_state->monitor_x = geometry.x;
      out_state->monitor_y = geometry.y;
      out_state->monitor_width = geometry.width;
      out_state->monitor_height = geometry.height;
      out_state->work_x = work.x;
      out_state->work_y = work.y;
      out_state->work_width = work.width;
      out_state->work_height = work.height;
    }
    out_state->scale_factor_percent =
        gdk_window_get_scale_factor(gdk_window) * 100;
    GdkWindowState state = gdk_window_get_state(gdk_window);
    out_state->minimized =
        (state & GDK_WINDOW_STATE_ICONIFIED) != 0 ? 1 : 0;
    out_state->maximized =
        (state & GDK_WINDOW_STATE_MAXIMIZED) != 0 ? 1 : 0;
    out_state->fullscreen =
        (state & GDK_WINDOW_STATE_FULLSCREEN) != 0 ? 1 : 0;
  }
  out_state->visible = gtk_widget_get_visible(window->window) ? 1 : 0;
  out_state->focused =
      gtk_window_has_toplevel_focus(GTK_WINDOW(window->window)) ? 1 : 0;
  out_state->always_on_top = window->always_on_top;
  gboolean dark = FALSE;
  GtkSettings *settings = gtk_settings_get_default();
  if (settings != NULL) {
    g_object_get(settings, "gtk-application-prefer-dark-theme", &dark, NULL);
    out_state->theme = dark ? 2 : 1;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_close_interception(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->close_interception_enabled = enabled != 0;
  if (!window->close_interception_enabled) {
    window->close_request_pending = 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_get_close_request(
    proton_engine_window_t *window, uint64_t *out_request_id,
    int32_t *out_pending, char *error, size_t error_len) {
  if (window == NULL || out_request_id == NULL || out_pending == NULL) {
    proton_engine_set_message(
        error, error_len,
        "window, out_request_id, and out_pending are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_request_id = window->close_request_id;
  *out_pending = window->close_request_pending;
  return PROTON_OK;
}

int32_t proton_engine_window_respond_close_request(
    proton_engine_window_t *window, uint64_t request_id, int32_t allow,
    char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!window->close_request_pending ||
      window->close_request_id != request_id) {
    proton_engine_set_message(error, error_len,
                              "window close request is no longer pending");
    return PROTON_ERR_STALE_WINDOW_REQUEST;
  }
  window->close_request_pending = 0;
  if (allow && !window->closed) {
    window->close_interception_bypass = 1;
    if (window->headless) {
      return proton_engine_window_close(window, error, error_len);
    }
    if (window->window != NULL) {
      gtk_window_close(GTK_WINDOW(window->window));
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t cef_url = {0};
  proton_engine_set_string(&cef_url, url != NULL ? url : "about:blank");
  frame->load_url(frame, &cef_url);
  cef_string_clear(&cef_url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t code = {0};
  cef_string_t script_url = {0};
  proton_engine_set_string(&code, script != NULL ? script : "");
  proton_engine_set_string(&script_url, "proton://eval.js");
  frame->execute_java_script(frame, &code, &script_url, 1);
  cef_string_clear(&code);
  cef_string_clear(&script_url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command_json(
      window->browser_session, window->browser, command_json, error,
      error_len);
}

int32_t proton_engine_window_respond_browser_request_json(
    proton_engine_window_t *window, const char *response_json,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_respond_json(
      window->browser_session, response_json, error, error_len);
}

int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len) {
  if (window == NULL || window->browser == NULL ||
      window->bridge_config_json == NULL) {
    proton_engine_set_message(error, error_len, "bridge is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (!proton_engine_bridge_send_event(window->browser, event_json)) {
    proton_engine_set_message(error, error_len,
                              "failed to send bridge event to renderer");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window) {
  return window != NULL ? window->public_window_id : PROTON_INVALID_HANDLE;
}

uint64_t proton_engine_window_bridge_revision(proton_engine_window_t *window) {
  return window != NULL
             ? proton_engine_bridge_lifecycle_revision(&window->bridge_lifecycle)
             : 0;
}

int32_t proton_engine_window_bridge_state_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_state_json(
      &window->bridge_lifecycle, buffer, buffer_len, out_required_len);
}

int32_t proton_engine_window_take_bridge_failure_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_take_failure_json(
      &window->bridge_lifecycle, buffer, buffer_len, out_required_len);
}

#endif
