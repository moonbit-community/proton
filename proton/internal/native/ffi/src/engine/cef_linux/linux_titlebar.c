#if defined(__linux__)

#include "linux_internal.h"

#include <stdint.h>
#include <string.h>

#include <gdk/gdkx.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>

static int proton_linux_titlebar_point_in_rect(
    proton_linux_titlebar_point_t point,
    proton_linux_titlebar_rect_t rect) {
  const int64_t right = (int64_t)rect.x + rect.width;
  const int64_t bottom = (int64_t)rect.y + rect.height;
  return rect.width > 0 && rect.height > 0 && point.x >= rect.x &&
         (int64_t)point.x < right && point.y >= rect.y &&
         (int64_t)point.y < bottom;
}

int proton_linux_titlebar_device_to_logical(int coordinate,
                                            int device_extent,
                                            int logical_extent) {
  if (device_extent <= 0 || logical_extent <= 0) {
    return coordinate;
  }
  return (int)(((int64_t)coordinate * logical_extent) / device_extent);
}

int proton_linux_titlebar_control_margin(int resize_handle) {
  return resize_handle > 0 ? (resize_handle + 1) / 2 : 0;
}

int proton_linux_titlebar_point_in_draggable_regions(
    proton_linux_titlebar_point_t point,
    size_t region_count,
    const proton_linux_titlebar_region_t *regions) {
  if (region_count == 0 || regions == NULL) {
    return 0;
  }
  int draggable = 0;
  for (size_t i = 0; i < region_count; i++) {
    proton_linux_titlebar_rect_t rect = {
        .x = regions[i].x,
        .y = regions[i].y,
        .width = regions[i].width,
        .height = regions[i].height,
    };
    if (regions[i].draggable &&
        proton_linux_titlebar_point_in_rect(point, rect)) {
      draggable = 1;
    }
  }
  if (!draggable) {
    return 0;
  }
  for (size_t i = 0; i < region_count; i++) {
    proton_linux_titlebar_rect_t rect = {
        .x = regions[i].x,
        .y = regions[i].y,
        .width = regions[i].width,
        .height = regions[i].height,
    };
    if (!regions[i].draggable &&
        proton_linux_titlebar_point_in_rect(point, rect)) {
      return 0;
    }
  }
  return 1;
}

proton_linux_titlebar_hit_t proton_linux_titlebar_hit_test(
    const proton_linux_titlebar_hit_test_input_t *input) {
  if (input == NULL || input->width <= 0 || input->height <= 0) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  const proton_linux_titlebar_point_t point = input->point;
  if (point.x < 0 || point.x >= input->width || point.y < 0 ||
      point.y >= input->height) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }

  if (proton_linux_titlebar_point_in_rect(point, input->controls)) {
    return PROTON_LINUX_TITLEBAR_HIT_CONTROLS;
  }

  if (!input->maximized && input->resize_handle > 0) {
    const int on_left = point.x < input->resize_handle;
    const int on_right = point.x >= input->width - input->resize_handle;
    const int on_top = point.y < input->resize_handle;
    const int on_bottom = point.y >= input->height - input->resize_handle;
    if (on_top && on_left) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST;
    }
    if (on_top && on_right) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_EAST;
    }
    if (on_bottom && on_left) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_WEST;
    }
    if (on_bottom && on_right) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST;
    }
    if (on_left) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_WEST;
    }
    if (on_right) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST;
    }
    if (on_top) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH;
    }
    if (on_bottom) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH;
    }
  }

  if (input->draggable_regions_reported) {
    return proton_linux_titlebar_point_in_draggable_regions(
               point, input->draggable_region_count,
               input->draggable_regions)
               ? PROTON_LINUX_TITLEBAR_HIT_DRAG
               : PROTON_LINUX_TITLEBAR_HIT_CLIENT;
  }
  if (proton_linux_titlebar_point_in_rect(point, input->fallback_drag)) {
    return PROTON_LINUX_TITLEBAR_HIT_DRAG;
  }
  return PROTON_LINUX_TITLEBAR_HIT_CLIENT;
}

static int proton_engine_window_is_maximized(proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL ||
      gtk_widget_get_window(window->window) == NULL) {
    return 0;
  }
  return (gdk_window_get_state(gtk_widget_get_window(window->window)) &
          GDK_WINDOW_STATE_MAXIMIZED) != 0;
}

void proton_engine_overlay_update_maximize_button(
    proton_engine_window_t *window) {
  if (window == NULL || window->maximize_image == NULL ||
      window->maximize_button == NULL) {
    return;
  }
  const int maximized = proton_engine_window_is_maximized(window);
  gtk_image_set_from_icon_name(
      GTK_IMAGE(window->maximize_image),
      maximized ? "window-restore-symbolic" : "window-maximize-symbolic",
      GTK_ICON_SIZE_MENU);
  const char *label = maximized ? window->titlebar_restore_label
                                : window->titlebar_maximize_label;
  gtk_widget_set_tooltip_text(window->maximize_button, label);
  atk_object_set_name(gtk_widget_get_accessible(window->maximize_button),
                      label);
}

void proton_engine_overlay_toggle_maximize(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL) {
    return;
  }
  if (proton_engine_window_is_maximized(window)) {
    gtk_window_unmaximize(GTK_WINDOW(window->window));
  } else {
    gtk_window_maximize(GTK_WINDOW(window->window));
  }
}

static void proton_engine_overlay_minimize(GtkButton *button,
                                           gpointer user_data) {
  (void)button;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL && window->window != NULL) {
    gtk_window_iconify(GTK_WINDOW(window->window));
  }
}

static void proton_engine_overlay_maximize(GtkButton *button,
                                           gpointer user_data) {
  (void)button;
  proton_engine_overlay_toggle_maximize(
      (proton_engine_window_t *)user_data);
}

static void proton_engine_overlay_close(GtkButton *button,
                                        gpointer user_data) {
  (void)button;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL && window->window != NULL) {
    gtk_window_close(GTK_WINDOW(window->window));
  }
}

gboolean proton_engine_overlay_window_state(
    GtkWidget *widget,
    GdkEventWindowState *event,
    gpointer user_data) {
  (void)widget;
  (void)event;
  proton_engine_overlay_update_maximize_button(
      (proton_engine_window_t *)user_data);
  proton_engine_overlay_update_input_shape(
      (proton_engine_window_t *)user_data);
  proton_engine_window_update_controls_overlay(
      (proton_engine_window_t *)user_data);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return FALSE;
}

int proton_engine_overlay_resize_handle(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL) {
    return 0;
  }
  int themed_handle = 0;
  gtk_widget_style_get(window->window, "decoration-resize-handle",
                       &themed_handle, NULL);
  return themed_handle > 1 ? (themed_handle + 1) / 2 : themed_handle;
}

static void proton_engine_overlay_region_union(
    cairo_region_t *region,
    proton_linux_titlebar_rect_t rect) {
  if (region == NULL || rect.width <= 0 || rect.height <= 0) {
    return;
  }
  cairo_rectangle_int_t cairo_rect = {
      .x = rect.x,
      .y = rect.y,
      .width = rect.width,
      .height = rect.height,
  };
  cairo_region_union_rectangle(region, &cairo_rect);
}

static void proton_engine_overlay_region_subtract(
    cairo_region_t *region,
    proton_linux_titlebar_rect_t rect) {
  if (region == NULL || rect.width <= 0 || rect.height <= 0) {
    return;
  }
  cairo_rectangle_int_t cairo_rect = {
      .x = rect.x,
      .y = rect.y,
      .width = rect.width,
      .height = rect.height,
  };
  cairo_region_subtract_rectangle(region, &cairo_rect);
}

void proton_engine_overlay_update_input_shape(
    proton_engine_window_t *window) {
  if (window == NULL || !window->titlebar_overlay ||
      window->window == NULL || window->browser_host == NULL) {
    return;
  }
  const int width = gtk_widget_get_allocated_width(window->browser_host);
  const int height = gtk_widget_get_allocated_height(window->browser_host);
  if (width <= 0 || height <= 0) {
    return;
  }

  cairo_region_t *region = cairo_region_create();
  if (region == NULL) {
    return;
  }
  const int resize_handle = proton_engine_overlay_resize_handle(window);
  if (!proton_engine_window_is_maximized(window) && resize_handle > 0) {
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){0, 0, width, resize_handle});
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){0, height - resize_handle,
                                               width, resize_handle});
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){0, 0, resize_handle, height});
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){width - resize_handle, 0,
                                               resize_handle, height});
  }

  if (window->draggable_regions_reported) {
    for (size_t i = 0; i < window->draggable_region_count; i++) {
      if (!window->draggable_regions[i].draggable) {
        continue;
      }
      proton_engine_overlay_region_union(
          region,
          (proton_linux_titlebar_rect_t){
              window->draggable_regions[i].x,
              window->draggable_regions[i].y,
              window->draggable_regions[i].width,
              window->draggable_regions[i].height,
          });
    }
    for (size_t i = 0; i < window->draggable_region_count; i++) {
      if (window->draggable_regions[i].draggable) {
        continue;
      }
      proton_engine_overlay_region_subtract(
          region,
          (proton_linux_titlebar_rect_t){
              window->draggable_regions[i].x,
              window->draggable_regions[i].y,
              window->draggable_regions[i].width,
              window->draggable_regions[i].height,
          });
    }
  } else {
    const int fallback_width =
        window->minimize_button != NULL
            ? gtk_widget_get_allocated_width(window->minimize_button)
            : 0;
    const int controls_height =
        window->overlay_controls != NULL
            ? gtk_widget_get_allocated_height(window->overlay_controls)
            : 0;
    const int fallback_height =
        controls_height > resize_handle ? controls_height - resize_handle
                                        : controls_height;
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){
                    resize_handle,
                    resize_handle,
                    fallback_width,
                    fallback_height,
                });
  }

  if (window->overlay_controls != NULL) {
    int controls_x = 0;
    int controls_y = 0;
    if (gtk_widget_translate_coordinates(window->overlay_controls,
                                         window->browser_host, 0, 0,
                                         &controls_x, &controls_y)) {
      proton_engine_overlay_region_subtract(
          region, (proton_linux_titlebar_rect_t){
                      controls_x,
                      controls_y,
                      gtk_widget_get_allocated_width(window->overlay_controls),
                      gtk_widget_get_allocated_height(
                          window->overlay_controls),
                  });
    }
  }

  cairo_rectangle_int_t bounds = {0, 0, width, height};
  cairo_region_intersect_rectangle(region, &bounds);
  GdkWindow *top_gdk_window = gtk_widget_get_window(window->window);
  if (top_gdk_window == NULL || !GDK_IS_X11_WINDOW(top_gdk_window)) {
    cairo_region_destroy(region);
    return;
  }
  GdkDisplay *gdk_display = gdk_window_get_display(top_gdk_window);
  Display *display = GDK_WINDOW_XDISPLAY(top_gdk_window);
  const Window parent = GDK_WINDOW_XID(top_gdk_window);
  XWindowAttributes parent_attributes;
  if (!XGetWindowAttributes(display, parent, &parent_attributes) ||
      parent_attributes.width <= 0 || parent_attributes.height <= 0) {
    cairo_region_destroy(region);
    return;
  }
  const unsigned int device_width = (unsigned int)parent_attributes.width;
  const unsigned int device_height = (unsigned int)parent_attributes.height;

  gdk_x11_display_error_trap_push(gdk_display);
  if (window->overlay_input_window == NULL) {
    XSetWindowAttributes attributes = {
        .event_mask = ButtonPressMask,
    };
    const Window input_window = XCreateWindow(
        display, parent, 0, 0, device_width, device_height, 0, 0, InputOnly,
        CopyFromParent, CWEventMask, &attributes);
    window->overlay_input_window = gdk_x11_window_foreign_new_for_display(
        gdk_display, input_window);
    if (window->overlay_input_window == NULL) {
      XDestroyWindow(display, input_window);
    } else {
      gdk_window_add_filter(window->overlay_input_window,
                            proton_engine_x11_event_filter, NULL);
      gdk_window_set_events(window->overlay_input_window,
                            GDK_BUTTON_PRESS_MASK);
      XWindowAttributes input_attributes;
      if (XGetWindowAttributes(display, input_window, &input_attributes)) {
        XSelectInput(display, input_window,
                     input_attributes.your_event_mask | ButtonPressMask);
      }
    }
  }
  if (window->overlay_input_window != NULL) {
    const Window input_window = GDK_WINDOW_XID(window->overlay_input_window);
    XMoveResizeWindow(display, input_window, 0, 0, device_width,
                      device_height);
    gdk_window_input_shape_combine_region(window->overlay_input_window, region,
                                          0, 0);
    XMapRaised(display, input_window);
  }
  XSync(display, False);
  (void)gdk_x11_display_error_trap_pop(gdk_display);
  cairo_region_destroy(region);
}

static GtkWidget *proton_engine_overlay_button(
    const char *icon_name,
    const char *style_class,
    const char *label,
    GCallback callback,
    proton_engine_window_t *window,
    GtkWidget **out_image) {
  GtkWidget *button = gtk_button_new();
  GtkWidget *image =
      gtk_image_new_from_icon_name(icon_name, GTK_ICON_SIZE_MENU);
  if (button == NULL || image == NULL) {
    if (button != NULL) {
      gtk_widget_destroy(button);
    }
    return NULL;
  }
  gtk_button_set_image(GTK_BUTTON(button), image);
  gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(button, FALSE);
  gtk_widget_set_tooltip_text(button, label);
  atk_object_set_name(gtk_widget_get_accessible(button), label);
  GtkStyleContext *context = gtk_widget_get_style_context(button);
  gtk_style_context_add_class(context, GTK_STYLE_CLASS_FLAT);
  gtk_style_context_add_class(context, "titlebutton");
  gtk_style_context_add_class(context, style_class);
  g_signal_connect(button, "clicked", callback, window);
  if (out_image != NULL) {
    *out_image = image;
  }
  return button;
}

int proton_engine_overlay_create_controls(
    proton_engine_window_t *window) {
  if (window == NULL || window->overlay == NULL) {
    return 0;
  }
  GtkWidget *event_box = gtk_event_box_new();
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  if (event_box == NULL || box == NULL) {
    if (event_box != NULL) {
      gtk_widget_destroy(event_box);
    }
    if (box != NULL) {
      gtk_widget_destroy(box);
    }
    return 0;
  }

  window->minimize_button = proton_engine_overlay_button(
      "window-minimize-symbolic", "minimize", window->titlebar_minimize_label,
      G_CALLBACK(proton_engine_overlay_minimize), window, NULL);
  window->maximize_button = proton_engine_overlay_button(
      "window-maximize-symbolic", "maximize", window->titlebar_maximize_label,
      G_CALLBACK(proton_engine_overlay_maximize), window,
      &window->maximize_image);
  window->close_button = proton_engine_overlay_button(
      "window-close-symbolic", "close", window->titlebar_close_label,
      G_CALLBACK(proton_engine_overlay_close), window, NULL);
  if (window->minimize_button == NULL || window->maximize_button == NULL ||
      window->close_button == NULL) {
    gtk_widget_destroy(event_box);
    return 0;
  }

  gtk_box_pack_start(GTK_BOX(box), window->minimize_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), window->maximize_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), window->close_button, FALSE, FALSE, 0);
  gtk_container_add(GTK_CONTAINER(event_box), box);
  gtk_event_box_set_visible_window(GTK_EVENT_BOX(event_box), TRUE);
  gtk_widget_set_app_paintable(event_box, TRUE);
  GdkScreen *screen = gtk_widget_get_screen(window->window);
  GdkVisual *rgba_visual =
      screen != NULL ? gdk_screen_get_rgba_visual(screen) : NULL;
  if (rgba_visual != NULL) {
    gtk_widget_set_visual(event_box, rgba_visual);
  }
  gtk_widget_set_name(event_box, "proton-overlay-controls");
  GtkCssProvider *provider = gtk_css_provider_new();
  if (provider != NULL) {
    gtk_css_provider_load_from_data(
        provider,
        "#proton-overlay-controls { background-color: transparent; "
        "background-image: none; }"
        "button { background-color: transparent; background-image: none; "
        "border-color: transparent; box-shadow: none; }"
        "button:hover { background-color: alpha(@theme_fg_color, 0.08); }"
        "button:active { background-color: alpha(@theme_fg_color, 0.14); }"
        "button.close:hover { background-color: #e81123; color: white; }"
        "button.close:active { background-color: #c50f1f; color: white; }",
        -1, NULL);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(event_box), GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(window->minimize_button),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(window->maximize_button),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(window->close_button),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
  }
  gtk_widget_set_halign(event_box, GTK_ALIGN_END);
  gtk_widget_set_valign(event_box, GTK_ALIGN_START);
  const int resize_handle = proton_engine_overlay_resize_handle(window);
  gtk_widget_set_margin_top(
      event_box, proton_linux_titlebar_control_margin(resize_handle));
  gtk_widget_set_margin_end(event_box, resize_handle);
  gtk_overlay_add_overlay(GTK_OVERLAY(window->overlay), event_box);
  gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(window->overlay), event_box,
                                       FALSE);
  window->overlay_controls = event_box;
  return 1;
}

static int proton_engine_x11_window_is_descendant(Display *display,
                                                   Window child,
                                                   Window ancestor) {
  if (display == NULL || child == None || ancestor == None) {
    return 0;
  }
  Window current = child;
  while (current != None) {
    if (current == ancestor) {
      return 1;
    }
    Window root = None;
    Window parent = None;
    Window *children = NULL;
    unsigned int child_count = 0;
    if (!XQueryTree(display, current, &root, &parent, &children,
                    &child_count)) {
      return 0;
    }
    if (children != NULL) {
      XFree(children);
    }
    if (parent == None || parent == current) {
      return 0;
    }
    current = parent;
  }
  return 0;
}

static int proton_engine_overlay_resize_direction(
    proton_linux_titlebar_hit_t hit) {
  switch (hit) {
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST:
    return PROTON_X11_MOVERESIZE_SIZE_TOP_LEFT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH:
    return PROTON_X11_MOVERESIZE_SIZE_TOP;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_EAST:
    return PROTON_X11_MOVERESIZE_SIZE_TOP_RIGHT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_WEST:
    return PROTON_X11_MOVERESIZE_SIZE_LEFT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST:
    return PROTON_X11_MOVERESIZE_SIZE_RIGHT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_WEST:
    return PROTON_X11_MOVERESIZE_SIZE_BOTTOM_LEFT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH:
    return PROTON_X11_MOVERESIZE_SIZE_BOTTOM;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST:
    return PROTON_X11_MOVERESIZE_SIZE_BOTTOM_RIGHT;
  default:
    return PROTON_X11_MOVERESIZE_SIZE_TOP;
  }
}

static int proton_engine_overlay_is_resize_hit(
    proton_linux_titlebar_hit_t hit) {
  return hit >= PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST &&
         hit <= PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST;
}

static void proton_engine_overlay_begin_moveresize(
    proton_engine_window_t *window,
    const XButtonEvent *event,
    int direction) {
  if (window == NULL || window->window == NULL || event == NULL ||
      event->display == NULL) {
    return;
  }
  GdkWindow *top_gdk_window = gtk_widget_get_window(window->window);
  if (top_gdk_window == NULL) {
    return;
  }
  const Atom moveresize =
      XInternAtom(event->display, "_NET_WM_MOVERESIZE", False);
  if (moveresize == None) {
    return;
  }
  XEvent message;
  memset(&message, 0, sizeof(message));
  message.xclient.type = ClientMessage;
  message.xclient.display = event->display;
  message.xclient.window = GDK_WINDOW_XID(top_gdk_window);
  message.xclient.message_type = moveresize;
  message.xclient.format = 32;
  message.xclient.data.l[0] = event->x_root;
  message.xclient.data.l[1] = event->y_root;
  message.xclient.data.l[2] = direction;
  message.xclient.data.l[3] = Button1;
  message.xclient.data.l[4] = 1;
  XUngrabPointer(event->display, event->time);
  (void)XSendEvent(event->display, event->root, False,
                   SubstructureRedirectMask | SubstructureNotifyMask,
                   &message);
  XFlush(event->display);
}

static proton_linux_titlebar_hit_t proton_engine_overlay_hit_test(
    proton_engine_window_t *window,
    Display *display,
    Window root,
    int root_x,
    int root_y) {
  if (window == NULL || window->browser_host == NULL || display == NULL) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  GdkWindow *browser_gdk_window = gtk_widget_get_window(window->browser_host);
  if (browser_gdk_window == NULL) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  const Window browser_xid = GDK_WINDOW_XID(browser_gdk_window);
  int device_x = 0;
  int device_y = 0;
  Window child = None;
  if (!XTranslateCoordinates(display, root, browser_xid, root_x, root_y,
                             &device_x, &device_y, &child)) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  XWindowAttributes attributes;
  if (!XGetWindowAttributes(display, browser_xid, &attributes)) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  const int logical_width = gtk_widget_get_allocated_width(window->browser_host);
  const int logical_height =
      gtk_widget_get_allocated_height(window->browser_host);
  proton_linux_titlebar_point_t point = {
      .x = proton_linux_titlebar_device_to_logical(
          device_x, attributes.width, logical_width),
      .y = proton_linux_titlebar_device_to_logical(
          device_y, attributes.height, logical_height),
  };

  proton_linux_titlebar_rect_t controls = {0};
  if (window->overlay_controls != NULL) {
    int controls_x = 0;
    int controls_y = 0;
    if (gtk_widget_translate_coordinates(window->overlay_controls,
                                         window->browser_host, 0, 0,
                                         &controls_x, &controls_y)) {
      controls.x = controls_x;
      controls.y = controls_y;
      controls.width =
          gtk_widget_get_allocated_width(window->overlay_controls);
      controls.height =
          gtk_widget_get_allocated_height(window->overlay_controls);
    }
  }

  const int resize_handle = proton_engine_overlay_resize_handle(window);
  const int fallback_width =
      window->minimize_button != NULL
          ? gtk_widget_get_allocated_width(window->minimize_button)
          : 0;
  proton_linux_titlebar_hit_test_input_t input = {
      .point = point,
      .width = logical_width,
      .height = logical_height,
      .resize_handle = resize_handle,
      .maximized = proton_engine_window_is_maximized(window),
      .controls = controls,
      .fallback_drag =
          {
              .x = resize_handle,
              .y = resize_handle,
              .width = fallback_width,
              .height =
                  controls.height > resize_handle
                      ? controls.height - resize_handle
                      : controls.height,
          },
      .draggable_regions_reported = window->draggable_regions_reported,
      .draggable_region_count = window->draggable_region_count,
      .draggable_regions = window->draggable_regions,
  };
  return proton_linux_titlebar_hit_test(&input);
}

static int proton_engine_overlay_is_double_click(
    proton_engine_window_t *window,
    const XButtonEvent *event) {
  if (window == NULL || event == NULL || window->last_drag_click_time == 0) {
    return 0;
  }
  GtkSettings *settings = gtk_settings_get_default();
  gint double_click_time = 0;
  gint double_click_distance = 0;
  if (settings != NULL) {
    g_object_get(settings, "gtk-double-click-time", &double_click_time,
                 "gtk-double-click-distance", &double_click_distance, NULL);
  }
  const guint32 elapsed = event->time - window->last_drag_click_time;
  return double_click_time > 0 && elapsed <= (guint32)double_click_time &&
         abs(event->x_root - window->last_drag_click_x) <=
             double_click_distance &&
         abs(event->y_root - window->last_drag_click_y) <=
             double_click_distance;
}

GdkFilterReturn proton_engine_x11_event_filter(GdkXEvent *xevent,
                                               GdkEvent *event,
                                               gpointer user_data) {
  (void)event;
  (void)user_data;
  XEvent *native_event = (XEvent *)xevent;
  if (native_event == NULL || native_event->type != ButtonPress ||
      native_event->xbutton.button != Button1) {
    return GDK_FILTER_CONTINUE;
  }
  Display *display = native_event->xbutton.display;
  for (proton_engine_window_t *window = proton_engine_windows_head();
       window != NULL;
       window = window->next) {
    if (!window->titlebar_overlay || window->window == NULL) {
      continue;
    }
    GdkWindow *top_gdk_window = gtk_widget_get_window(window->window);
    if (top_gdk_window == NULL ||
        !proton_engine_x11_window_is_descendant(
            display, native_event->xbutton.window,
            GDK_WINDOW_XID(top_gdk_window))) {
      continue;
    }
    proton_linux_titlebar_hit_t hit = proton_engine_overlay_hit_test(
        window, display, native_event->xbutton.root,
        native_event->xbutton.x_root, native_event->xbutton.y_root);
    if (proton_engine_overlay_is_resize_hit(hit)) {
      proton_engine_overlay_begin_moveresize(
          window, &native_event->xbutton,
          proton_engine_overlay_resize_direction(hit));
      return GDK_FILTER_REMOVE;
    }
    if (hit != PROTON_LINUX_TITLEBAR_HIT_DRAG) {
      return GDK_FILTER_CONTINUE;
    }
    if (proton_engine_overlay_is_double_click(window,
                                              &native_event->xbutton)) {
      window->last_drag_click_time = 0;
      proton_engine_overlay_toggle_maximize(window);
      return GDK_FILTER_REMOVE;
    }
    window->last_drag_click_time = native_event->xbutton.time;
    window->last_drag_click_x = native_event->xbutton.x_root;
    window->last_drag_click_y = native_event->xbutton.y_root;
    proton_engine_overlay_begin_moveresize(
        window, &native_event->xbutton, PROTON_X11_MOVERESIZE_MOVE);
    return GDK_FILTER_REMOVE;
  }
  return GDK_FILTER_CONTINUE;
}

#endif
