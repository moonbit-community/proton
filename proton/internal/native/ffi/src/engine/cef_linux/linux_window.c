#if defined(__linux__)

#include "linux_internal.h"
#include "../../proton_config.h"
#include "../../proton_event.h"

#include "../cef_common/bridge_request.h"
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

int proton_engine_x11_window_is_focused(Display *display,
                                        Window browser_window) {
  if (display == NULL || browser_window == None) {
    return 0;
  }
  Window focused = None;
  int revert_to = RevertToNone;
  XGetInputFocus(display, &focused, &revert_to);
  if (focused == None || focused == PointerRoot) {
    return 0;
  }

  GdkDisplay *gdk_display = gdk_x11_lookup_xdisplay(display);
  if (gdk_display != NULL) {
    gdk_x11_display_error_trap_push(gdk_display);
  }
  int is_focused = 0;
  Window current = focused;
  while (current != None) {
    if (current == browser_window) {
      is_focused = 1;
      break;
    }
    Window root = None;
    Window parent = None;
    Window *children = NULL;
    unsigned int child_count = 0;
    const int queried = XQueryTree(display, current, &root, &parent, &children,
                                   &child_count);
    if (children != NULL) {
      XFree(children);
    }
    if (!queried) {
      break;
    }
    if (parent == None || parent == current) {
      break;
    }
    current = parent;
  }
  if (gdk_display != NULL) {
    XSync(display, False);
    if (gdk_x11_display_error_trap_pop(gdk_display) != 0) {
      is_focused = 0;
    }
  }
  return is_focused;
}

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
  if (window->aspect_ratio > 0.0) {
    geometry.min_aspect = window->aspect_ratio;
    geometry.max_aspect = window->aspect_ratio;
    hints = (GdkWindowHints)(hints | GDK_HINT_ASPECT);
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
      !window->close_authorized) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      (void)proton_event_publish_window_close_requested(
          window->public_window_id, window->close_request_id);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return TRUE;
  }
  if (proton_engine_window_browser(window) != NULL) {
    cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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
    if (proton_engine_window_browser(window) == NULL) {
      proton_engine_window_mark_closed(window);
    }
  }
}

void proton_engine_sync_browser_bounds(proton_engine_window_t *window) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    return;
  }
  if (window->headless) {
    cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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
  cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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
  if (window != NULL && proton_engine_window_browser(window) != NULL) {
    cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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

static void proton_engine_window_active_notify(GObject *object,
                                               GParamSpec *parameter,
                                               gpointer user_data) {
  if (gtk_window_is_active(GTK_WINDOW(object))) {
    gtk_window_set_urgency_hint(GTK_WINDOW(object), FALSE);
  }
  proton_engine_window_state_notify(object, parameter, user_data);
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
  if (window == NULL ||
      proton_browser_lifecycle_client(window->browser_lifecycle) == NULL ||
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

  cef_dictionary_value_t *extra_info =
      proton_engine_bridge_renderer_extra_info(window->bridge_config);
  cef_browser_t *created_browser = cef_browser_host_create_browser_sync(
      &window_info, proton_browser_lifecycle_client(window->browser_lifecycle), &url, &browser_settings,
      extra_info, NULL);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (created_browser == NULL) {
    proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
    proton_engine_set_message(error, error_len, "browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_lifecycle_adopt_created(window->browser_lifecycle,
                                         created_browser);
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
  window->fullscreenable = 1;
  window->enabled = 1;
  window->bridge_config = config.bridge_config;
  proton_bridge_config_retain(window->bridge_config);
  window->max_bridge_payload_bytes = config.max_bridge_payload_bytes;
  window->browser_session = proton_browser_session_create(
      &config.browser_policy, proton_engine_browser_signal, NULL);
  window->browser_lifecycle = proton_browser_lifecycle_create(
      runtime->browsers, PROTON_BROWSER_ROLE_MAIN, window, NULL);
  if (window->browser_session == NULL || window->browser_lifecycle == NULL) {
    proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
    proton_internal_bridge_config_destroy(window->bridge_config);
    proton_browser_session_destroy(window->browser_session);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser state");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_session_bind_window(window->browser_session,
                                     config.public_window);
  proton_browser_session_bind_lifecycle(window->browser_session,
                                        window->browser_lifecycle);
  proton_engine_client_t *client = proton_engine_client_create(
      window->browser_lifecycle);
  if (client == NULL) {
    proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
    proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
    proton_browser_session_destroy(window->browser_session);
    proton_internal_bridge_config_destroy(window->bridge_config);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_lifecycle_set_client(window->browser_lifecycle,
                                      &client->client);

  if (!window->headless) {
    window->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    if (window->window == NULL) {
      proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
      proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
      proton_browser_session_destroy(window->browser_session);
      proton_internal_bridge_config_destroy(window->bridge_config);
      free(window);
      proton_engine_set_message(error, error_len, "window creation failed");
      return PROTON_ERR_PLATFORM;
    }
    window->root_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    if (window->root_box == NULL) {
      gtk_widget_destroy(window->window);
      proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
      proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
      proton_browser_session_destroy(window->browser_session);
      proton_internal_bridge_config_destroy(window->bridge_config);
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
        proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
        proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
        proton_browser_session_destroy(window->browser_session);
        proton_internal_bridge_config_destroy(window->bridge_config);
        free(window);
        proton_engine_set_message(error, error_len,
                                  "overlay container creation failed");
        return PROTON_ERR_PLATFORM;
      }
    }
    window->browser_host = gtk_drawing_area_new();
    if (window->browser_host == NULL) {
      gtk_widget_destroy(window->window);
      proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
      proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
      proton_browser_session_destroy(window->browser_session);
      proton_internal_bridge_config_destroy(window->bridge_config);
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
        proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
        proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
        proton_browser_session_destroy(window->browser_session);
        proton_internal_bridge_config_destroy(window->bridge_config);
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
        proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
        proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
        proton_browser_session_destroy(window->browser_session);
        proton_internal_bridge_config_destroy(window->bridge_config);
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
                     G_CALLBACK(proton_engine_window_active_notify), window);
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
    proton_browser_lifecycle_creation_failed(window->browser_lifecycle);
    if (window->window != NULL) {
      gtk_widget_destroy(window->window);
    }
    proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
    proton_browser_session_destroy(window->browser_session);
    proton_internal_bridge_config_destroy(window->bridge_config);
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
  if (window->closed && proton_engine_window_browser(window) == NULL) {
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
  if (proton_engine_window_browser(window) != NULL) {
    proton_engine_bridge_pending_remove_browser(
        window->runtime,
        proton_browser_lifecycle_browser_id(window->browser_lifecycle));
    window->destroy_requested = 1;
    window->closing = 1;
    proton_engine_window_close_views(window);
    proton_browser_lifecycle_request_close(window->browser_lifecycle, 1);
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
    if (proton_engine_window_browser(window) != NULL) {
      cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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

int32_t proton_engine_window_show_inactive(proton_engine_window_t *window,
                                           char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) return proton_engine_window_show(window, error, error_len);
  gtk_widget_show_all(window->window);
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
    if (proton_engine_window_browser(window) != NULL) {
      cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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
      !window->close_authorized) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      (void)proton_event_publish_window_close_requested(
          window->public_window_id, window->close_request_id);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
  }
  if (!window->headless) {
    gtk_window_close(GTK_WINDOW(window->window));
    return PROTON_OK;
  }
  if (proton_engine_window_browser(window) != NULL) {
    cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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
  if (proton_engine_window_browser(window) != NULL) {
    cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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

int32_t proton_engine_window_set_icon(proton_engine_window_t *window,
                                      const char *path, char *error,
                                      size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (path == NULL || path[0] == '\0') {
    proton_engine_set_message(error, error_len, "icon path is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window icon is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  GError *load_error = NULL;
  gtk_window_set_icon_from_file(GTK_WINDOW(window->window), path, &load_error);
  if (load_error != NULL) {
    proton_engine_set_message(error, error_len, load_error->message);
    g_error_free(load_error);
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_parent(proton_engine_window_t *window,
                                        proton_engine_window_t *parent,
                                        int32_t modal, char *error,
                                        size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (modal != 0 && modal != 1) {
    proton_engine_set_message(error, error_len, "modal must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window parenting is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  GtkWindow *parent_window = parent != NULL && parent->window != NULL
                                 ? GTK_WINDOW(parent->window)
                                 : NULL;
  gtk_window_set_transient_for(GTK_WINDOW(window->window), parent_window);
  gtk_window_set_modal(GTK_WINDOW(window->window),
                       parent_window != NULL && modal != 0);
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

int32_t proton_engine_window_set_content_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len, "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->width = width;
    window->height = height;
    proton_engine_sync_browser_bounds(window);
    return PROTON_OK;
  }
  GtkAllocation allocation;
  gtk_widget_get_allocation(window->browser_host, &allocation);
  int outer_width = 0;
  int outer_height = 0;
  gtk_window_get_size(GTK_WINDOW(window->window), &outer_width, &outer_height);
  int target_outer_width = outer_width + width - allocation.width;
  int target_outer_height = outer_height + height - allocation.height;
  gtk_window_resize(GTK_WINDOW(window->window), target_outer_width,
                    target_outer_height);
  return PROTON_OK;
}

int32_t proton_engine_window_get_content_size(
    proton_engine_window_t *window, int32_t *out_width, int32_t *out_height,
    char *error, size_t error_len) {
  if (window == NULL || out_width == NULL || out_height == NULL) {
    proton_engine_set_message(error, error_len, "window and outputs are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    *out_width = window->width;
    *out_height = window->height;
    return PROTON_OK;
  }
  GtkAllocation allocation;
  gtk_widget_get_allocation(window->browser_host, &allocation);
  *out_width = allocation.width > 0 ? allocation.width : window->width;
  *out_height = allocation.height > 0 ? allocation.height : window->height;
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

int32_t proton_engine_window_set_aspect_ratio(
    proton_engine_window_t *window, double aspect_ratio, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (isnan(aspect_ratio) || aspect_ratio < 0.0) {
    proton_engine_set_message(error, error_len,
                              "aspect ratio must be non-negative");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window aspect ratio is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  window->aspect_ratio = aspect_ratio;
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

int32_t proton_engine_window_set_content_protection(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (enabled != 0 && enabled != 1) {
    proton_engine_set_message(error, error_len, "enabled must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "content protection is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron exposes this API on macOS and Windows only; Linux is a success no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_minimizable(
    proton_engine_window_t *window, int32_t minimizable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (minimizable != 0 && minimizable != 1) {
    proton_engine_set_message(error, error_len, "minimizable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window minimizability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron exposes this setter on macOS and Windows; Linux is a success no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_maximizable(
    proton_engine_window_t *window, int32_t maximizable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (maximizable != 0 && maximizable != 1) {
    proton_engine_set_message(error, error_len, "maximizable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window maximizability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron exposes this setter on macOS and Windows; Linux is a success no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_closable(
    proton_engine_window_t *window, int32_t closable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (closable != 0 && closable != 1) {
    proton_engine_set_message(error, error_len, "closable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window closability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron exposes this setter on macOS and Windows; Linux is a success no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_button_visibility(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (visible != 0 && visible != 1) {
    proton_engine_set_message(error, error_len, "visible must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window buttons are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_focusable(
    proton_engine_window_t *window, int32_t focusable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (focusable != 0 && focusable != 1) {
    proton_engine_set_message(error, error_len, "focusable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window focusability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Electron exposes this setter on macOS and Windows; Linux is a success no-op.
  return PROTON_OK;
}

int32_t proton_engine_window_set_fullscreenable(
    proton_engine_window_t *window, int32_t fullscreenable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (fullscreenable != 0 && fullscreenable != 1) {
    proton_engine_set_message(error, error_len,
                              "fullscreenable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window fullscreenability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  window->fullscreenable = fullscreenable;
  return PROTON_OK;
}

int32_t proton_engine_window_set_has_shadow(
    proton_engine_window_t *window, int32_t has_shadow, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (has_shadow != 0 && has_shadow != 1) {
    proton_engine_set_message(error, error_len, "has_shadow must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window shadow is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_ignore_mouse_events(
    proton_engine_window_t *window, int32_t ignore, int32_t forward,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if ((ignore != 0 && ignore != 1) || (forward != 0 && forward != 1)) {
    proton_engine_set_message(error, error_len,
                              "ignore and forward must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "mouse event handling is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Linux window-manager input-shape support varies; keep this API a stable
  // successful no-op until a compositor-independent implementation exists.
  return PROTON_OK;
}

int32_t proton_engine_window_set_background_color(
    proton_engine_window_t *window, uint32_t color, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window background is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  GdkRGBA native_color = {
      .red = (double)((color >> 16) & 0xff) / 255.0,
      .green = (double)((color >> 8) & 0xff) / 255.0,
      .blue = (double)(color & 0xff) / 255.0,
      .alpha = (double)((color >> 24) & 0xff) / 255.0,
  };
  gtk_widget_override_background_color(window->window, GTK_STATE_FLAG_NORMAL,
                                       &native_color);
  gtk_widget_override_background_color(window->root_box, GTK_STATE_FLAG_NORMAL,
                                       &native_color);
  return PROTON_OK;
}

int32_t proton_engine_window_set_visible_on_all_workspaces(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (visible != 0 && visible != 1) {
    proton_engine_set_message(error, error_len, "visible must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "workspace visibility is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (visible) {
    gtk_window_stick(GTK_WINDOW(window->window));
  } else {
    gtk_window_unstick(GTK_WINDOW(window->window));
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_enabled(proton_engine_window_t *window,
                                         int32_t enabled, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (enabled != 0 && enabled != 1) {
    proton_engine_set_message(error, error_len, "enabled must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) return PROTON_OK;
  gtk_widget_set_sensitive(window->window, enabled != 0);
  window->enabled = enabled;
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
  gboolean urgent =
      flash != 0 && !gtk_window_is_active(GTK_WINDOW(window->window));
  gtk_window_set_urgency_hint(GTK_WINDOW(window->window), urgent);
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
    if (proton_engine_window_browser(window) == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser is not initialized");
      return PROTON_ERR_NOT_INITIALIZED;
    }
    cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
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
  case PROTON_ENGINE_WINDOW_SET_KIOSK:
    if (action->value != 0 &&
        (action->kind == PROTON_ENGINE_WINDOW_SET_KIOSK ||
         window->fullscreenable)) {
      gtk_window_fullscreen(GTK_WINDOW(window->window));
    } else if (action->value == 0) {
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
  if (window->close_interception_enabled) {
    window->close_authorized = 0;
  }
  if (!window->close_interception_enabled) {
    window->close_request_pending = 0;
  }
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
    window->close_authorized = 1;
    if (window->headless) {
      return proton_engine_window_close(window, error, error_len);
    }
    if (window->window != NULL) {
      gtk_window_close(GTK_WINDOW(window->window));
    }
  } else if (!allow) {
    window->close_authorized = 0;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = proton_engine_window_browser(window)->get_main_frame(proton_engine_window_browser(window));
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
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = proton_engine_window_browser(window)->get_main_frame(proton_engine_window_browser(window));
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

int32_t proton_engine_window_browser_command(
    proton_engine_window_t *window, const char *command, int32_t download_id,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command(
      window->browser_session, proton_engine_window_browser(window), command,
      download_id, error, error_len);
}

int32_t proton_engine_window_get_browser_focus_state(
    proton_engine_window_t *window, int32_t *out_focused,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (out_focused == NULL) {
    proton_engine_set_message(error, error_len, "focus output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    return proton_browser_headless_is_focused(
        proton_engine_window_browser(window), out_focused, error, error_len);
  }
  cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
  if (host == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser host is not available");
    return PROTON_ERR_ENGINE;
  }
  const Window browser_window = (Window)host->get_window_handle(host);
  host->base.release((cef_base_ref_counted_t *)host);
  GdkWindow *host_window = window->browser_host == NULL
                               ? NULL
                               : gtk_widget_get_window(window->browser_host);
  Display *display = host_window == NULL ? NULL
                                         : GDK_WINDOW_XDISPLAY(host_window);
  if (display == NULL || browser_window == None) {
    proton_engine_set_message(error, error_len,
                              "browser window is not available");
    return PROTON_ERR_ENGINE;
  }
  *out_focused =
      proton_engine_x11_window_is_focused(display, browser_window);
  return PROTON_OK;
}

int32_t proton_engine_window_get_devtools_state(
    proton_engine_window_t *window, int32_t *out_opened,
    char *error, size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_is_devtools_opened(
      proton_engine_window_browser(window), out_opened, error, error_len);
}

int32_t proton_engine_window_get_navigation_state(
    proton_engine_window_t *window, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_navigation_state(
      proton_engine_window_browser(window), out_can_go_back, out_can_go_forward, error, error_len);
}

int32_t proton_engine_window_download_url(
    proton_engine_window_t *window, const char *url, char *error,
    size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_download_url(proton_engine_window_browser(window), url, error, error_len);
}

int32_t proton_engine_window_print(
    proton_engine_window_t *window, char *error, size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_print(proton_engine_window_browser(window), error, error_len);
}

int32_t proton_engine_window_print_to_pdf(
    proton_engine_window_t *window, const char *path, int32_t landscape,
    int32_t print_background, double scale, double paper_width,
    double paper_height, int32_t prefer_css_page_size, int32_t margin_type,
    double margin_top, double margin_right, double margin_bottom,
    double margin_left, const char *page_ranges,
    int32_t display_header_footer, const char *header_template,
    const char *footer_template, int32_t generate_tagged_pdf,
    int32_t generate_document_outline, int32_t *out_request_id,
    char *error, size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_print_to_pdf(
      window->browser_session, proton_engine_window_browser(window), path, landscape,
      print_background, scale, paper_width, paper_height,
      prefer_css_page_size, margin_type, margin_top, margin_right,
      margin_bottom, margin_left, page_ranges, display_header_footer,
      header_template, footer_template, generate_tagged_pdf,
      generate_document_outline, out_request_id, error, error_len);
}

int32_t proton_engine_window_find_in_page(
    proton_engine_window_t *window, const char *text, int32_t forward,
    int32_t match_case, int32_t find_next, int32_t *out_request_id,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_find_in_page(
      window->browser_session, proton_engine_window_browser(window), text, forward, match_case,
      find_next, out_request_id, error, error_len);
}

int32_t proton_engine_window_stop_find_in_page(
    proton_engine_window_t *window, int32_t clear_selection, char *error,
    size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_stop_find_in_page(
      proton_engine_window_browser(window), clear_selection, error, error_len);
}

int32_t proton_engine_window_set_audio_muted(
    proton_engine_window_t *window, int32_t muted, char *error,
    size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_set_audio_muted(
      proton_engine_window_browser(window), muted, error, error_len);
}

int32_t proton_engine_window_is_audio_muted(
    proton_engine_window_t *window, int32_t *out_muted, char *error,
    size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_is_audio_muted(
      proton_engine_window_browser(window), out_muted, error, error_len);
}

int32_t proton_engine_window_get_browser_url(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  int32_t status = proton_browser_session_copy_url(
      window->browser_session, buffer, buffer_len, out_required_len);
  if (status != PROTON_OK) {
    proton_engine_set_message(error, error_len,
                              "browser URL buffer is too small");
  }
  return status;
}

int32_t proton_engine_window_get_browser_title(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  int32_t status = proton_browser_session_copy_title(
      window->browser_session, buffer, buffer_len, out_required_len);
  if (status != PROTON_OK) {
    proton_engine_set_message(error, error_len,
                              "browser title buffer is too small");
  }
  return status;
}

int32_t proton_engine_window_get_browser_loading(
    proton_engine_window_t *window, int32_t *out_is_loading, char *error,
    size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      out_is_loading == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session and loading output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_is_loading = proton_browser_session_is_loading(window->browser_session);
  return PROTON_OK;
}

int32_t proton_engine_window_respond_browser_request(
    proton_engine_window_t *window, uint64_t request_id, const char *action,
    const char *path,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_respond(window->browser_session, request_id,
                                        action, path, error, error_len);
}

int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len) {
  if (window == NULL || proton_engine_window_browser(window) == NULL ||
      window->bridge_config == NULL) {
    proton_engine_set_message(error, error_len, "bridge is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (!proton_engine_bridge_send_event(proton_engine_window_browser(window), event_json)) {
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

int32_t proton_engine_window_bridge_state_field(
    proton_engine_window_t *window, int32_t field, char *buffer,
    int32_t buffer_len, int32_t *out_required_len, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_copy_state_field(
      &window->bridge_lifecycle, field, buffer, buffer_len, out_required_len);
}

int32_t proton_engine_window_bridge_failure_present(
    proton_engine_window_t *window, int32_t *out_present, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_failure_present(
      &window->bridge_lifecycle, out_present);
}

int32_t proton_engine_window_bridge_failure_field(
    proton_engine_window_t *window, int32_t field, char *buffer,
    int32_t buffer_len, int32_t *out_required_len, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_copy_failure_field(
      &window->bridge_lifecycle, field, buffer, buffer_len, out_required_len);
}

int32_t proton_engine_window_bridge_failure_int_field(
    proton_engine_window_t *window, int32_t field, int32_t *out_value,
    int32_t *out_present, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_failure_int_field(
      &window->bridge_lifecycle, field, out_value, out_present);
}

int32_t proton_engine_window_clear_bridge_failure(
    proton_engine_window_t *window, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  proton_engine_bridge_lifecycle_clear_failure(&window->bridge_lifecycle);
  return PROTON_OK;
}

#endif
