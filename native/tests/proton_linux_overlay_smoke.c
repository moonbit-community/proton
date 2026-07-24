#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include "proton_native.h"

#include <X11/Xlib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int expect_status(const char *name, int32_t actual, int32_t expected) {
  if (actual == expected) {
    return 0;
  }
  char error[1024] = {0};
  (void)proton_last_error_message(error, (int32_t)sizeof(error));
  fprintf(stderr, "%s expected status %d, got %d: %s\n", name, expected,
          actual, error);
  return 1;
}

static int file_contains(const char *path, const char *needle) {
  FILE *file = fopen(path, "rb");
  if (file == NULL) {
    return 0;
  }
  fseek(file, 0, SEEK_END);
  long length = ftell(file);
  fseek(file, 0, SEEK_SET);
  if (length <= 0) {
    fclose(file);
    return 0;
  }
  char *text = (char *)malloc((size_t)length + 1);
  if (text == NULL) {
    fclose(file);
    return 0;
  }
  size_t read = fread(text, 1, (size_t)length, file);
  fclose(file);
  text[read] = '\0';
  int found = strstr(text, needle) != NULL;
  free(text);
  return found;
}

static int pump_until_log(proton_runtime_id_t runtime,
                          const char *log_path,
                          const char *needle) {
  for (int i = 0; i < 800; i++) {
    if (proton_runtime_do_message_loop_work(runtime) != PROTON_OK) {
      return 0;
    }
    if (file_contains(log_path, needle)) {
      return 1;
    }
    usleep(10000);
  }
  return 0;
}

static Window find_window_by_title(Display *display,
                                   Window parent,
                                   const char *title) {
  Window root = None;
  Window parent_return = None;
  Window *children = NULL;
  unsigned int child_count = 0;
  if (!XQueryTree(display, parent, &root, &parent_return, &children,
                  &child_count)) {
    return None;
  }
  Window found = None;
  for (unsigned int i = 0; i < child_count && found == None; i++) {
    char *name = NULL;
    if (XFetchName(display, children[i], &name) && name != NULL) {
      if (strcmp(name, title) == 0) {
        found = children[i];
      }
      XFree(name);
    }
    if (found == None) {
      found = find_window_by_title(display, children[i], title);
    }
  }
  if (children != NULL) {
    XFree(children);
  }
  return found;
}

static Window find_overlay_input_window(Display *display,
                                        Window parent,
                                        Window *out_parent,
                                        XWindowAttributes *out_attributes) {
  Window root = None;
  Window parent_return = None;
  Window *children = NULL;
  unsigned int child_count = 0;
  if (!XQueryTree(display, parent, &root, &parent_return, &children,
                  &child_count)) {
    return None;
  }
  Window found = None;
  for (unsigned int i = 0; i < child_count; i++) {
    XWindowAttributes attributes;
    if (XGetWindowAttributes(display, children[i], &attributes) &&
        attributes.class == InputOnly &&
        (attributes.all_event_masks & ButtonPressMask) != 0) {
      found = children[i];
      if (out_attributes != NULL) {
        *out_attributes = attributes;
      }
      if (out_parent != NULL) {
        *out_parent = parent;
      }
      break;
    }
    found = find_overlay_input_window(display, children[i], out_parent,
                                      out_attributes);
    if (found != None) {
      break;
    }
  }
  if (children != NULL) {
    XFree(children);
  }
  return found;
}

static int send_button_press(Display *display,
                             Window top,
                             Window input,
                             int x,
                             int y) {
  XWindowAttributes top_attributes;
  if (!XGetWindowAttributes(display, top, &top_attributes)) {
    return 0;
  }
  int root_x = 0;
  int root_y = 0;
  Window child = None;
  if (!XTranslateCoordinates(display, top, top_attributes.root, x, y,
                             &root_x, &root_y, &child)) {
    return 0;
  }
  XEvent event;
  memset(&event, 0, sizeof(event));
  event.xbutton.type = ButtonPress;
  event.xbutton.display = display;
  event.xbutton.window = input;
  event.xbutton.root = top_attributes.root;
  event.xbutton.subwindow = None;
  event.xbutton.time = CurrentTime;
  event.xbutton.x = x;
  event.xbutton.y = y;
  event.xbutton.x_root = root_x;
  event.xbutton.y_root = root_y;
  event.xbutton.state = 0;
  event.xbutton.button = Button1;
  event.xbutton.same_screen = True;
  const int sent =
      XSendEvent(display, input, False, ButtonPressMask, &event) != 0;
  XFlush(display);
  return sent;
}

static int verify_overlay_input_path(proton_runtime_id_t runtime,
                                     const char *log_path) {
  Display *display = XOpenDisplay(NULL);
  if (display == NULL) {
    fprintf(stderr, "failed to open X display for overlay input smoke\n");
    return 0;
  }
  const Window root = DefaultRootWindow(display);
  const Window top =
      find_window_by_title(display, root, "Proton Linux Overlay Smoke");
  if (top == None) {
    fprintf(stderr, "overlay top-level X11 window was not found\n");
    XCloseDisplay(display);
    return 0;
  }
  Window input_parent = None;
  XWindowAttributes top_attributes;
  XWindowAttributes input_attributes;
  const Window input =
      find_overlay_input_window(display, top, &input_parent,
                                &input_attributes);
  if (input == None) {
    fprintf(stderr, "overlay InputOnly X11 window was not found\n");
    XCloseDisplay(display);
    return 0;
  }
  if (input_parent == None ||
      !XGetWindowAttributes(display, input_parent, &top_attributes)) {
    fprintf(stderr, "overlay input parent attributes were not available\n");
    XCloseDisplay(display);
    return 0;
  }
  if (input_attributes.width != top_attributes.width ||
      input_attributes.height != top_attributes.height) {
    fprintf(stderr,
            "overlay input size %dx%d does not match top-level %dx%d\n",
            input_attributes.width, input_attributes.height,
            top_attributes.width, top_attributes.height);
    XCloseDisplay(display);
    return 0;
  }

  const int drag_x = top_attributes.width / 8;
  const int drag_y = top_attributes.height * 20 / 520;
  if (!send_button_press(display, input_parent, input, drag_x, drag_y) ||
      !pump_until_log(runtime, log_path, "overlay_moveresize direction=8")) {
    fprintf(stderr, "overlay drag press did not reach moveresize\n");
    XCloseDisplay(display);
    return 0;
  }

  if (!send_button_press(display, input_parent, input, 1,
                         top_attributes.height / 2) ||
      !pump_until_log(runtime, log_path, "overlay_moveresize direction=7")) {
    fprintf(stderr, "overlay resize press did not reach moveresize\n");
    XCloseDisplay(display);
    return 0;
  }
  XCloseDisplay(display);
  return 1;
}

int main(void) {
  const char *runtime_root = getenv("PROTON_TEST_ENGINE_ROOT");
  const char *helper_path = getenv("PROTON_TEST_HELPER_PATH");
  const char *cache_root = getenv("PROTON_TEST_CACHE_ROOT");
  const char *log_path = getenv("PROTON_TEST_LOG_PATH");
  if (runtime_root == NULL || helper_path == NULL || cache_root == NULL ||
      log_path == NULL) {
    fprintf(stderr, "Linux overlay smoke environment is incomplete\n");
    return 1;
  }
  mkdir(cache_root, 0700);
  unlink(log_path);
  setenv("PROTON_NATIVE_LOG", log_path, 1);

  char runtime_config[16384];
  snprintf(runtime_config, sizeof(runtime_config),
           "{\"abi_version\":1,\"runtime_root\":\"%s\","
           "\"helper_path\":\"%s\",\"cache_dir\":\"%s\"}",
           runtime_root, helper_path, cache_root);
  proton_runtime_id_t runtime = PROTON_INVALID_HANDLE;
  if (expect_status("runtime_create",
                    proton_runtime_create_json(runtime_config, &runtime),
                    PROTON_OK)) {
    return 1;
  }

  proton_window_id_t window = PROTON_INVALID_HANDLE;
  if (expect_status(
          "overlay window_create",
          proton_window_create_json(
              runtime,
              "{\"abi_version\":1,\"title\":\"Proton Linux Overlay "
              "Smoke\",\"width\":800,\"height\":520,"
              "\"titlebar_style\":\"overlay\"}",
              &window),
          PROTON_OK)) {
    proton_runtime_destroy(runtime);
    return 1;
  }
  if (expect_status("overlay window_show", proton_window_show(window),
                    PROTON_OK)) {
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }

  const char *html =
      "<!doctype html><html><head><style>html,body{margin:0;width:100%;"
      "height:100%}.drag{height:40px;-webkit-app-region:drag}.control{"
      "margin-left:280px;width:240px;height:32px;-webkit-app-region:no-drag}"
      "</style></head><body><div class='drag'><button class='control'>"
      "control</button></div><script>setTimeout(()=>{document.querySelector("
      "'.drag').style.webkitAppRegion='drag'},0)</script></body></html>";
  if (expect_status("overlay load_html",
                    proton_window_load_html(window, html,
                                            "proton://overlay-smoke/"),
                    PROTON_OK)) {
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }

  if (!pump_until_log(runtime, log_path, "overlay_ready controls=")) {
    fprintf(stderr, "GTK overlay controls were not created\n");
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }
  if (file_contains(log_path, "overlay_ready controls=0x0")) {
    fprintf(stderr, "GTK overlay controls have no allocation\n");
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }
  if (!pump_until_log(runtime, log_path, "draggable_regions browser=")) {
    fprintf(stderr, "CEF draggable regions did not reach the Linux engine\n");
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }
  if (!verify_overlay_input_path(runtime, log_path)) {
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }
  if (expect_status("overlay window_destroy", proton_window_destroy(window),
                    PROTON_OK) ||
      expect_status("overlay runtime_destroy", proton_runtime_destroy(runtime),
                    PROTON_OK)) {
    return 1;
  }
  return 0;
}
