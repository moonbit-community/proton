#if defined(__linux__)

#include "internal.h"

#include "../../proton_event.h"
#include "../cef_common/message.h"

#include <gtk/gtk.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct proton_engine_linux_dialog_request {
  int64_t id;
  int64_t public_window;
  proton_engine_runtime_t *runtime;
  proton_engine_window_t *window;
  GtkWidget *dialog;
  proton_engine_linux_dialog_kind_t kind;
  int completed;
  struct proton_engine_linux_dialog_request *next;
} proton_engine_linux_dialog_request_t;

static int64_t g_next_dialog_id = 1;
static proton_engine_linux_dialog_request_t *g_dialog_requests = NULL;

static void proton_engine_file_dialog_set_default_size(
    GtkWindow *dialog, GtkWidget *parent);

static void proton_engine_publish_dialog_completed(int64_t window,
                                                   int64_t request_id,
                                                   int32_t status,
                                                   const char *result,
                                                   const char *error_message) {
  proton_event_t *event = proton_event_create(PROTON_EVENT_DIALOG_COMPLETED);
  if (event == NULL) {
    return;
  }
  event->window = window;
  event->request_id = request_id;
  event->int_a = status;
  if (proton_event_set_text(
          &event->text_a, status == PROTON_OK && result != NULL ? result : "") &&
      proton_event_set_text(&event->text_b,
                            error_message != NULL ? error_message : "")) {
    (void)proton_event_publish(event);
  } else {
    proton_event_destroy(event);
  }
}

static void proton_engine_dialog_remove(
    proton_engine_linux_dialog_request_t *request) {
  proton_engine_linux_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    if (*cursor == request) {
      *cursor = request->next;
      free(request);
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static void proton_engine_dialog_response(GtkDialog *dialog,
                                          gint response_id,
                                          gpointer user_data) {
  proton_engine_linux_dialog_request_t *request =
      (proton_engine_linux_dialog_request_t *)user_data;
  if (request == NULL || request->completed) {
    return;
  }
  int32_t status = PROTON_OK;
  const char *result = "";
  const char *error_message = NULL;
  char *result_utf8 = NULL;
  GError *conversion_error = NULL;
  if (request->kind == PROTON_ENGINE_LINUX_DIALOG_CONFIRM) {
    result = response_id == GTK_RESPONSE_OK ? "1" : "0";
  } else if (request->kind == PROTON_ENGINE_LINUX_DIALOG_FILE &&
             response_id == GTK_RESPONSE_ACCEPT) {
    char *filename =
        gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
    if (filename != NULL) {
      result_utf8 =
          g_filename_to_utf8(filename, -1, NULL, NULL, &conversion_error);
      g_free(filename);
    }
    if (result_utf8 != NULL) {
      result = result_utf8;
    } else {
      status = PROTON_ERR_PLATFORM;
      error_message = conversion_error != NULL
                          ? conversion_error->message
                          : "failed to read the selected path";
    }
  }
  request->completed = 1;
  request->dialog = NULL;
  g_signal_handlers_disconnect_by_data(dialog, request);
  gtk_widget_destroy(GTK_WIDGET(dialog));
  proton_engine_publish_dialog_completed(request->public_window, request->id,
                                         status, result, error_message);
  if (conversion_error != NULL) {
    g_error_free(conversion_error);
  }
  g_free(result_utf8);
  proton_engine_dialog_remove(request);
}

static void proton_engine_dialog_destroyed(GtkWidget *dialog,
                                           gpointer user_data) {
  proton_engine_linux_dialog_request_t *request =
      (proton_engine_linux_dialog_request_t *)user_data;
  if (request == NULL) {
    return;
  }
  request->dialog = NULL;
  if (!request->completed) {
    request->completed = 1;
    const char *result =
        request->kind == PROTON_ENGINE_LINUX_DIALOG_CONFIRM ? "0" : "";
    proton_engine_publish_dialog_completed(request->public_window, request->id,
                                           PROTON_OK, result, NULL);
    proton_engine_dialog_remove(request);
  }
  (void)dialog;
}

static int32_t proton_engine_dialog_register(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    GtkWidget *dialog, proton_engine_linux_dialog_kind_t kind,
    int64_t *out_dialog, char *error, size_t error_len) {
  proton_engine_linux_dialog_request_t *request =
      (proton_engine_linux_dialog_request_t *)calloc(1, sizeof(*request));
  if (request == NULL) {
    gtk_widget_destroy(dialog);
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog request");
    return PROTON_ERR_ENGINE;
  }
  request->id = g_next_dialog_id++;
  if (g_next_dialog_id <= 0) {
    g_next_dialog_id = 1;
  }
  request->runtime = runtime;
  request->window = window;
  request->public_window = proton_engine_window_public_id(window);
  request->dialog = dialog;
  request->kind = kind;
  request->next = g_dialog_requests;
  g_dialog_requests = request;
  g_signal_connect(dialog, "response", G_CALLBACK(proton_engine_dialog_response),
                   request);
  g_signal_connect(dialog, "destroy", G_CALLBACK(proton_engine_dialog_destroyed),
                   request);
  gtk_widget_show_all(dialog);
  if (kind == PROTON_ENGINE_LINUX_DIALOG_FILE && window != NULL &&
      window->window != NULL) {
    proton_engine_file_dialog_set_default_size(GTK_WINDOW(dialog),
                                               window->window);
  }
  GdkWindow *dialog_window = gtk_widget_get_window(dialog);
  guint32 present_time = dialog_window != NULL
                             ? gdk_x11_get_server_time(dialog_window)
                             : GDK_CURRENT_TIME;
  gtk_window_present_with_time(GTK_WINDOW(dialog), present_time);
  *out_dialog = request->id;
  return PROTON_OK;
}

static GtkMessageType proton_engine_dialog_message_type(int32_t level) {
  switch (level) {
  case 1:
    return GTK_MESSAGE_WARNING;
  case 2:
    return GTK_MESSAGE_ERROR;
  default:
    return GTK_MESSAGE_INFO;
  }
}

static int32_t proton_engine_begin_message_dialog(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    const char *title_utf8, int32_t title_len, const char *message_utf8,
    int32_t message_len, int32_t level, int64_t *out_dialog, char *error,
    size_t error_len) {
  if (runtime == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog runtime and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  if (runtime->headless || (window != NULL && window->headless)) {
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window != NULL && window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (runtime->dialog_ok_label[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog label is not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  char *title = g_strndup(title_utf8 != NULL ? title_utf8 : "",
                          title_len > 0 ? (gsize)title_len : 0);
  char *message = g_strndup(message_utf8 != NULL ? message_utf8 : "",
                            message_len > 0 ? (gsize)message_len : 0);
  if (title == NULL || message == NULL) {
    g_free(title);
    g_free(message);
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog text");
    return PROTON_ERR_ENGINE;
  }
  GtkWidget *dialog = gtk_message_dialog_new(
      window != NULL ? GTK_WINDOW(window->window) : NULL,
      GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
      proton_engine_dialog_message_type(level), GTK_BUTTONS_NONE, "%s",
      message);
  g_free(message);
  if (dialog == NULL) {
    g_free(title);
    proton_engine_set_message(error, error_len,
                              "failed to create native message dialog");
    return PROTON_ERR_PLATFORM;
  }
  if (title[0] != '\0') {
    gtk_window_set_title(GTK_WINDOW(dialog), title);
  }
  gtk_dialog_add_button(GTK_DIALOG(dialog), runtime->dialog_ok_label,
                        GTK_RESPONSE_OK);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_OK);
  g_free(title);
  return proton_engine_dialog_register(
      runtime, window, dialog, PROTON_ENGINE_LINUX_DIALOG_MESSAGE, out_dialog,
      error, error_len);
}

static void proton_engine_dialog_cancel_matching(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    int match_window) {
  proton_engine_linux_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    proton_engine_linux_dialog_request_t *request = *cursor;
    if (request->runtime != runtime ||
        (match_window && request->window != window)) {
      cursor = &request->next;
      continue;
    }
    *cursor = request->next;
    if (request->dialog != NULL) {
      g_signal_handlers_disconnect_by_data(request->dialog, request);
      gtk_widget_destroy(request->dialog);
    }
    free(request);
  }
}

void proton_engine_dialog_cancel_runtime(
    proton_engine_runtime_t *runtime) {
  proton_engine_dialog_cancel_matching(runtime, NULL, 0);
}

void proton_engine_dialog_cancel_window(proton_engine_window_t *window) {
  if (window != NULL) {
    proton_engine_dialog_cancel_matching(window->runtime, window, 1);
  }
}

int32_t proton_engine_window_cancel_dialog(proton_engine_window_t *window,
                                           int64_t dialog,
                                           char *error,
                                           size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  proton_engine_linux_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    proton_engine_linux_dialog_request_t *request = *cursor;
    if (request->window != window || request->id != dialog) {
      cursor = &request->next;
      continue;
    }
    *cursor = request->next;
    request->next = NULL;
    request->completed = 1;
    if (request->dialog != NULL) {
      g_signal_handlers_disconnect_by_data(request->dialog, request);
      gtk_widget_destroy(request->dialog);
    }
    free(request);
    return PROTON_OK;
  }
  return PROTON_OK;
}

int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog, char *error, size_t error_len) {
  return proton_engine_begin_message_dialog(
      runtime, NULL, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_message_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_begin_message_dialog(
      window != NULL ? window->runtime : NULL, window, title_utf8, title_len,
      message_utf8, message_len, level, out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_confirm_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  if (window == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog window and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  proton_engine_runtime_t *runtime = window->runtime;
  if (window->headless || (runtime != NULL && runtime->headless)) {
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (runtime == NULL || runtime->dialog_ok_label[0] == '\0' ||
      runtime->dialog_cancel_label[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog labels are not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  char *title = g_strndup(title_utf8 != NULL ? title_utf8 : "",
                          title_len > 0 ? (gsize)title_len : 0);
  char *message = g_strndup(message_utf8 != NULL ? message_utf8 : "",
                            message_len > 0 ? (gsize)message_len : 0);
  if (title == NULL || message == NULL) {
    g_free(title);
    g_free(message);
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog text");
    return PROTON_ERR_ENGINE;
  }
  GtkWidget *dialog = gtk_message_dialog_new(
      GTK_WINDOW(window->window),
      GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
      proton_engine_dialog_message_type(level), GTK_BUTTONS_NONE, "%s",
      message);
  g_free(message);
  if (dialog == NULL) {
    g_free(title);
    proton_engine_set_message(error, error_len,
                              "failed to create native confirm dialog");
    return PROTON_ERR_PLATFORM;
  }
  if (title[0] != '\0') {
    gtk_window_set_title(GTK_WINDOW(dialog), title);
  }
  g_free(title);
  gtk_dialog_add_button(GTK_DIALOG(dialog), runtime->dialog_cancel_label,
                        GTK_RESPONSE_CANCEL);
  gtk_dialog_add_button(GTK_DIALOG(dialog), runtime->dialog_ok_label,
                        GTK_RESPONSE_OK);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_OK);
  return proton_engine_dialog_register(
      runtime, window, dialog, PROTON_ENGINE_LINUX_DIALOG_CONFIRM, out_dialog,
      error, error_len);
}

typedef enum proton_engine_linux_file_dialog_mode {
  PROTON_ENGINE_LINUX_FILE_DIALOG_OPEN = 0,
  PROTON_ENGINE_LINUX_FILE_DIALOG_SAVE = 1,
  PROTON_ENGINE_LINUX_FILE_DIALOG_CHOOSE_DIRECTORY = 2,
} proton_engine_linux_file_dialog_mode_t;

static int32_t proton_engine_file_dialog_set_initial_path(
    GtkFileChooser *chooser, const char *path_utf8, int32_t path_len,
    proton_engine_linux_file_dialog_mode_t mode, char *error,
    size_t error_len) {
  if (path_utf8 == NULL || path_len <= 0) {
    return PROTON_OK;
  }
  GError *conversion_error = NULL;
  char *path =
      g_filename_from_utf8(path_utf8, path_len, NULL, NULL, &conversion_error);
  if (path == NULL) {
    proton_engine_set_message(
        error, error_len,
        conversion_error != NULL ? conversion_error->message
                                 : "dialog path is not valid UTF-8");
    if (conversion_error != NULL) {
      g_error_free(conversion_error);
    }
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char *absolute_path = g_canonicalize_filename(path, NULL);
  g_free(path);
  if (absolute_path == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate the dialog path");
    return PROTON_ERR_ENGINE;
  }
  if (mode == PROTON_ENGINE_LINUX_FILE_DIALOG_CHOOSE_DIRECTORY) {
    char *directory = NULL;
    if (g_file_test(absolute_path, G_FILE_TEST_IS_DIR)) {
      directory = g_strdup(absolute_path);
    } else {
      directory = g_path_get_dirname(absolute_path);
    }
    if (directory != NULL &&
        g_file_test(directory, G_FILE_TEST_IS_DIR)) {
      (void)gtk_file_chooser_set_filename(chooser, directory);
    }
    g_free(directory);
  } else if (g_file_test(absolute_path, G_FILE_TEST_IS_DIR)) {
    (void)gtk_file_chooser_set_current_folder(chooser, absolute_path);
  } else if (mode == PROTON_ENGINE_LINUX_FILE_DIALOG_SAVE) {
    char *directory = g_path_get_dirname(absolute_path);
    char *name = g_path_get_basename(absolute_path);
    if (directory != NULL &&
        g_file_test(directory, G_FILE_TEST_IS_DIR)) {
      (void)gtk_file_chooser_set_current_folder(chooser, directory);
    }
    if (name != NULL && name[0] != '\0') {
      gtk_file_chooser_set_current_name(chooser, name);
    }
    g_free(directory);
    g_free(name);
  } else if (g_file_test(absolute_path, G_FILE_TEST_EXISTS)) {
    (void)gtk_file_chooser_set_filename(chooser, absolute_path);
  } else {
    char *directory = g_path_get_dirname(absolute_path);
    if (directory != NULL &&
        g_file_test(directory, G_FILE_TEST_IS_DIR)) {
      (void)gtk_file_chooser_set_current_folder(chooser, directory);
    }
    g_free(directory);
  }
  g_free(absolute_path);
  return PROTON_OK;
}

static void proton_engine_file_dialog_set_default_size(
    GtkWindow *dialog, GtkWidget *parent) {
  int width = 820;
  int height = 600;
  GdkWindow *parent_window = gtk_widget_get_window(parent);
  GdkDisplay *display = gtk_widget_get_display(parent);
  GdkMonitor *monitor = parent_window != NULL && display != NULL
                            ? gdk_display_get_monitor_at_window(display,
                                                                parent_window)
                            : NULL;
  if (monitor != NULL) {
    GdkRectangle workarea;
    gdk_monitor_get_workarea(monitor, &workarea);
    if (workarea.width > 64 && width > workarea.width - 64) {
      width = workarea.width - 64;
    }
    if (workarea.height > 64 && height > workarea.height - 64) {
      height = workarea.height - 64;
    }
  }
  gtk_window_set_default_size(dialog, width, height);
  gtk_window_resize(dialog, width, height);
}

static int32_t proton_engine_window_begin_file_dialog(
    proton_engine_window_t *window, const char *title_utf8, int32_t title_len,
    const char *path_utf8, int32_t path_len,
    proton_engine_linux_file_dialog_mode_t mode, int64_t *out_dialog,
    char *error, size_t error_len) {
  if (window == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog window and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  proton_engine_runtime_t *runtime = window->runtime;
  if (window->headless || (runtime != NULL && runtime->headless)) {
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (runtime == NULL || runtime->dialog_ok_label[0] == '\0' ||
      runtime->dialog_cancel_label[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog labels are not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  char *title = g_strndup(title_utf8 != NULL ? title_utf8 : "",
                          title_len > 0 ? (gsize)title_len : 0);
  if (title == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog title");
    return PROTON_ERR_ENGINE;
  }
  GtkFileChooserAction action = GTK_FILE_CHOOSER_ACTION_OPEN;
  const char *accept_label = runtime->dialog_ok_label;
  if (mode == PROTON_ENGINE_LINUX_FILE_DIALOG_SAVE) {
    action = GTK_FILE_CHOOSER_ACTION_SAVE;
  } else if (mode == PROTON_ENGINE_LINUX_FILE_DIALOG_CHOOSE_DIRECTORY) {
    action = GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;
  }
  GtkWidget *dialog = gtk_file_chooser_dialog_new(
      title, GTK_WINDOW(window->window), action, runtime->dialog_cancel_label,
      GTK_RESPONSE_CANCEL, accept_label, GTK_RESPONSE_ACCEPT, NULL);
  g_free(title);
  if (dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create native file dialog");
    return PROTON_ERR_PLATFORM;
  }
  gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
  gtk_window_set_destroy_with_parent(GTK_WINDOW(dialog), TRUE);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
  if (mode == PROTON_ENGINE_LINUX_FILE_DIALOG_SAVE) {
    gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dialog),
                                                   TRUE);
  }
  int32_t status = proton_engine_file_dialog_set_initial_path(
      GTK_FILE_CHOOSER(dialog), path_utf8, path_len, mode, error, error_len);
  if (status != PROTON_OK) {
    gtk_widget_destroy(dialog);
    return status;
  }
  return proton_engine_dialog_register(
      runtime, window, dialog, PROTON_ENGINE_LINUX_DIALOG_FILE, out_dialog,
      error, error_len);
}

int32_t proton_engine_window_begin_open_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_LINUX_FILE_DIALOG_OPEN, out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_save_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_LINUX_FILE_DIALOG_SAVE, out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_choose_directory_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_LINUX_FILE_DIALOG_CHOOSE_DIRECTORY, out_dialog, error,
      error_len);
}

#endif
