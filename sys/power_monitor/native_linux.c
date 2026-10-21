#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)

#include <gio/gio.h>
#include <dirent.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

void power_monitor_platform_init(power_monitor_state_t *state) {
  state->completion_fd = -1;
}

int32_t power_monitor_platform_query_idle(power_monitor_state_t *state) {
  state->idle_seconds = 0;
  return power_monitor_STATUS_OK;
}

static int read_int_from_file(const char *path) {
  FILE *f = fopen(path, "r");
  if (f == NULL) {
    return -1;
  }
  int value = -1;
  if (fscanf(f, "%d", &value) != 1) {
    value = -1;
  }
  fclose(f);
  return value;
}

int32_t power_monitor_platform_query_source(power_monitor_state_t *state) {
  DIR *dir = opendir("/sys/class/power_supply");
  if (dir == NULL) {
    state->source = power_monitor_SOURCE_UNKNOWN;
    state->has_battery_percent = 0;
    return power_monitor_STATUS_OK;
  }
  state->source = power_monitor_SOURCE_AC;
  state->has_battery_percent = 0;
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] == '.') {
      continue;
    }
    char type_path[512];
    char online_path[512];
    char capacity_path[512];
    snprintf(type_path, sizeof(type_path), "/sys/class/power_supply/%s/type",
             entry->d_name);
    snprintf(online_path, sizeof(online_path),
             "/sys/class/power_supply/%s/online", entry->d_name);
    snprintf(capacity_path, sizeof(capacity_path),
             "/sys/class/power_supply/%s/capacity", entry->d_name);

    FILE *type_f = fopen(type_path, "r");
    if (type_f == NULL) {
      continue;
    }
    char type_buf[32] = {0};
    if (fgets(type_buf, sizeof(type_buf), type_f) == NULL) {
      fclose(type_f);
      continue;
    }
    fclose(type_f);
    type_buf[strcspn(type_buf, "\n")] = '\0';

    if (strcmp(type_buf, "Mains") == 0) {
      int online = read_int_from_file(online_path);
      if (online == 1) {
        state->source = power_monitor_SOURCE_AC;
      }
    } else if (strcmp(type_buf, "Battery") == 0) {
      int capacity = read_int_from_file(capacity_path);
      if (capacity >= 0 && capacity <= 100) {
        state->battery_percent = capacity;
        state->has_battery_percent = 1;
      }
      int online = read_int_from_file(online_path);
      if (online == 0 && state->source != power_monitor_SOURCE_AC) {
        state->source = power_monitor_SOURCE_BATTERY;
      }
    }
  }
  closedir(dir);
  return power_monitor_STATUS_OK;
}

/* GIO owns transport establishment, authentication and method-call deadlines.
   It stays optional at runtime; only the Linux watcher loads it. */
#define GIO_FUNCTIONS(X) \
  X(main_context_new) X(main_context_unref) X(main_context_push_thread_default) \
  X(main_context_pop_thread_default) X(main_context_iteration) X(main_context_wakeup) \
  X(cancellable_new) X(cancellable_cancel) X(cancellable_is_cancelled) \
  X(dbus_connection_new_for_address) X(dbus_connection_new_for_address_finish) \
  X(dbus_connection_set_exit_on_close) X(dbus_connection_call) X(dbus_connection_call_finish) \
  X(dbus_connection_signal_subscribe) X(dbus_connection_signal_unsubscribe) \
  X(dbus_connection_close) X(dbus_connection_close_finish) \
  X(signal_connect_data) X(signal_handler_disconnect) \
  X(variant_new) X(variant_get_type_string) X(variant_get_child_value) \
  X(variant_get_boolean) X(variant_get_string) X(variant_lookup_value) X(variant_unref) \
  X(timeout_source_new) X(source_set_callback) X(source_attach) X(source_destroy) X(source_unref) \
  X(object_unref) X(error_free)

static struct {
#define DECLARE(name) __typeof__(&g_##name) name;
  GIO_FUNCTIONS(DECLARE)
#undef DECLARE
  int ready;
} g_gio;
static pthread_once_t gio_once = PTHREAD_ONCE_INIT;

static void power_monitor_load_gio_once(void) {
  void *lib = dlopen("libgio-2.0.so.0", RTLD_NOW | RTLD_LOCAL);
  if (lib == NULL) return;
#define LOAD(name) \
  g_gio.name = (__typeof__(g_gio.name))dlsym(lib, "g_" #name); \
  if (g_gio.name == NULL) { dlclose(lib); return; }
  GIO_FUNCTIONS(LOAD)
#undef LOAD
  g_gio.ready = 1;
}
#undef GIO_FUNCTIONS

static int power_monitor_load_gio(void) {
  pthread_once(&gio_once, power_monitor_load_gio_once);
  return g_gio.ready;
}

static void power_monitor_set_watch_error(power_monitor_state_t *state,
                                           const char *message) {
  pthread_mutex_lock(&state->event_lock);
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
  pthread_mutex_unlock(&state->event_lock);
}

/* All operation callbacks run on the worker's private GMainContext. Stop only
   cancels its GCancellable and wakes that context; it never joins the worker. */
typedef struct {
  power_monitor_state_t *state;
  GDBusConnection *connection;
  int completed;
  int succeeded;
  int timed_out;
  int disconnected;
} power_monitor_watch_t;

static void power_monitor_connected(GObject *source, GAsyncResult *result,
                                     gpointer data) {
  (void)source;
  power_monitor_watch_t *watch = data;
  GError *error = NULL;
  watch->connection = g_gio.dbus_connection_new_for_address_finish(result, &error);
  if (error != NULL) {
    power_monitor_set_watch_error(watch->state, error->message);
    g_gio.error_free(error);
  }
  watch->completed = 1;
}

static void power_monitor_called(GObject *source, GAsyncResult *result,
                                  gpointer data) {
  power_monitor_watch_t *watch = data;
  GError *error = NULL;
  GVariant *reply = g_gio.dbus_connection_call_finish((GDBusConnection *)source,
                                                     result, &error);
  watch->succeeded = reply != NULL;
  if (reply != NULL) g_gio.variant_unref(reply);
  if (error != NULL) {
    power_monitor_set_watch_error(watch->state, error->message);
    g_gio.error_free(error);
  }
  watch->completed = 1;
}

static void power_monitor_closed(GObject *source, GAsyncResult *result,
                                  gpointer data) {
  power_monitor_watch_t *watch = data;
  GError *error = NULL;
  g_gio.dbus_connection_close_finish((GDBusConnection *)source, result, &error);
  if (error != NULL) g_gio.error_free(error);
  watch->completed = 1;
}

static void power_monitor_disconnected(GDBusConnection *connection,
    gboolean remote_peer_vanished, GError *error, gpointer data) {
  (void)connection; (void)remote_peer_vanished;
  power_monitor_watch_t *watch = data;
  watch->disconnected = 1;
  power_monitor_set_watch_error(watch->state,
      error != NULL ? error->message : "D-Bus connection disconnected");
}

static gboolean power_monitor_startup_timeout(gpointer data) {
  power_monitor_watch_t *watch = data;
  watch->timed_out = 1;
  g_gio.cancellable_cancel(watch->state->watch_cancel);
  return G_SOURCE_REMOVE;
}

static void power_monitor_signal(GDBusConnection *connection,
    const gchar *sender, const gchar *path, const gchar *interface,
    const gchar *member, GVariant *parameters, gpointer data) {
  (void)connection; (void)sender;
  power_monitor_state_t *state = data;
  if (strcmp(interface, "org.freedesktop.login1.Manager") == 0 &&
      strcmp(member, "PrepareForSleep") == 0 &&
      strcmp(g_gio.variant_get_type_string(parameters), "(b)") == 0) {
    GVariant *value = g_gio.variant_get_child_value(parameters, 0);
    power_monitor_push_event(state, g_gio.variant_get_boolean(value)
        ? power_monitor_EVENT_SUSPEND : power_monitor_EVENT_RESUME);
    g_gio.variant_unref(value);
  } else if (strcmp(interface, "org.freedesktop.login1.Session") == 0) {
    if (strcmp(member, "Lock") == 0)
      power_monitor_push_event(state, power_monitor_EVENT_LOCK_SCREEN);
    else if (strcmp(member, "Unlock") == 0)
      power_monitor_push_event(state, power_monitor_EVENT_UNLOCK_SCREEN);
  } else if (strcmp(path, "/org/freedesktop/UPower") == 0 &&
             strcmp(interface, "org.freedesktop.DBus.Properties") == 0 &&
             strcmp(member, "PropertiesChanged") == 0 &&
             strcmp(g_gio.variant_get_type_string(parameters), "(sa{sv}as)") == 0) {
    GVariant *changed_interface = g_gio.variant_get_child_value(parameters, 0);
    int upower = strcmp(g_gio.variant_get_string(changed_interface, NULL),
                         "org.freedesktop.UPower") == 0;
    g_gio.variant_unref(changed_interface);
    if (!upower) return;
    GVariant *changed = g_gio.variant_get_child_value(parameters, 1);
    GVariant *value = g_gio.variant_lookup_value(changed, "OnBattery", NULL);
    if (value != NULL && strcmp(g_gio.variant_get_type_string(value), "b") == 0) {
      int source = g_gio.variant_get_boolean(value)
          ? power_monitor_SOURCE_BATTERY : power_monitor_SOURCE_AC;
      if (source != state->last_source) {
        state->last_source = source;
        power_monitor_push_event(state, source == power_monitor_SOURCE_BATTERY
            ? power_monitor_EVENT_ON_BATTERY : power_monitor_EVENT_ON_AC);
      }
    }
    if (value != NULL) g_gio.variant_unref(value);
    g_gio.variant_unref(changed);
  }
}

static void *power_monitor_linux_watch_thread_main(void *data) {
  power_monitor_state_t *state = data;
  power_monitor_watch_t watch = {.state = state};
  GMainContext *context = state->watch_context;
  GCancellable *cancel = state->watch_cancel;
  g_gio.main_context_push_thread_default(context);
  GSource *deadline = g_gio.timeout_source_new(5000);
  g_gio.source_set_callback(deadline, power_monitor_startup_timeout, &watch, NULL);
  g_gio.source_attach(deadline, context);
  const char *address = getenv("DBUS_SYSTEM_BUS_ADDRESS");
  if (address == NULL) address = "unix:path=/var/run/dbus/system_bus_socket";
  g_gio.dbus_connection_new_for_address(address,
      G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
      G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION,
      NULL, cancel, power_monitor_connected, &watch);
  while (!watch.completed) g_gio.main_context_iteration(context, TRUE);
  guint subscription = 0;
  gulong closed_handler = 0;
  if (watch.connection == NULL) goto finish;
  g_gio.dbus_connection_set_exit_on_close(watch.connection, FALSE);
  closed_handler = g_gio.signal_connect_data(watch.connection, "closed",
      (GCallback)power_monitor_disconnected, &watch, NULL, 0);
  subscription = g_gio.dbus_connection_signal_subscribe(watch.connection,
      NULL, NULL, NULL, NULL, NULL, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
      power_monitor_signal, state, NULL);
  if (subscription == 0) {
    power_monitor_set_watch_error(state, "subscribing to D-Bus signals failed");
    goto finish;
  }
  static const char *const rules[] = {
      "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'",
      "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
      "type='signal',interface='org.freedesktop.login1.Session',member='Unlock'",
      "type='signal',path='/org/freedesktop/UPower',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'",
  };
  for (size_t i = 0; i < sizeof(rules) / sizeof(rules[0]); i++) {
    watch.completed = 0;
    g_gio.dbus_connection_call(watch.connection, "org.freedesktop.DBus",
        "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch",
        g_gio.variant_new("(s)", rules[i]), NULL, G_DBUS_CALL_FLAGS_NONE,
        5000, cancel, power_monitor_called, &watch);
    while (!watch.completed) g_gio.main_context_iteration(context, TRUE);
    if (!watch.succeeded) goto finish;
  }
  g_gio.source_destroy(deadline);
  if (g_gio.cancellable_is_cancelled(cancel)) goto finish;
  pthread_mutex_lock(&state->event_lock);
  state->watch_started = 1;
  pthread_mutex_unlock(&state->event_lock);
  char ready = 1;
  ssize_t written;
  do { written = write(state->completion_fd, &ready, 1); }
  while (written < 0 && errno == EINTR);
  if (written != 1) {
    power_monitor_set_watch_error(state, "notifying watcher readiness failed");
    goto finish;
  }
  while (!g_gio.cancellable_is_cancelled(cancel) && !watch.disconnected)
    g_gio.main_context_iteration(context, TRUE);
finish:
  g_gio.source_destroy(deadline);
  g_gio.source_unref(deadline);
  if (watch.timed_out)
    power_monitor_set_watch_error(state, "D-Bus startup timed out after 5000ms");
  if (watch.connection != NULL) {
    if (subscription) g_gio.dbus_connection_signal_unsubscribe(watch.connection, subscription);
    if (closed_handler) g_gio.signal_handler_disconnect(watch.connection, closed_handler);
    watch.completed = 0;
    /* Closing a private connection does not require a reply from the bus. */
    g_gio.dbus_connection_close(watch.connection, NULL, power_monitor_closed, &watch);
    while (!watch.completed) g_gio.main_context_iteration(context, TRUE);
    g_gio.object_unref(watch.connection);
  }
  g_gio.main_context_pop_thread_default(context);
  pthread_mutex_lock(&state->event_lock);
  state->watch_started = 0;
  state->watch_cancel = NULL;
  state->watch_context = NULL;
  int fd = state->completion_fd;
  state->completion_fd = -1;
  pthread_mutex_unlock(&state->event_lock);
  g_gio.object_unref(cancel);
  g_gio.main_context_unref(context);
  /* The MoonBit scope retains state until EOF; no native access follows it. */
  close(fd);
  return NULL;
}

int32_t power_monitor_platform_start_watching(power_monitor_state_t *state) {
  state->watch_error[0] = '\0';
  if (!power_monitor_load_gio()) {
    power_monitor_set_watch_error(state, "libgio-2.0 unavailable");
    return power_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  power_monitor_platform_query_source(state);
  state->last_source = state->source;
  state->watch_cancel = g_gio.cancellable_new();
  state->watch_context = g_gio.main_context_new();
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  pthread_t thread;
  int result = pthread_create(&thread, &attr, power_monitor_linux_watch_thread_main, state);
  pthread_attr_destroy(&attr);
  if (result != 0) {
    g_gio.object_unref(state->watch_cancel);
    g_gio.main_context_unref(state->watch_context);
    state->watch_cancel = NULL;
    state->watch_context = NULL;
    power_monitor_set_watch_error(state, "pthread_create failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state) {
  pthread_mutex_lock(&state->event_lock);
  if (state->watch_cancel != NULL) {
    g_gio.cancellable_cancel(state->watch_cancel);
    g_gio.main_context_wakeup(state->watch_context);
  }
  pthread_mutex_unlock(&state->event_lock);
  return power_monitor_STATUS_OK;
}

#endif
