#include "native_stub.h"

#ifdef __APPLE__
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef const void *proton_cf_type_ref;
typedef const void *proton_cf_string_ref;
typedef const void *proton_cf_allocator_ref;
typedef const struct __proton_cf_array *proton_cf_array_ref;
typedef const struct __proton_cf_dictionary *proton_cf_dictionary_ref;
typedef const struct __proton_cf_number *proton_cf_number_ref;
typedef long proton_cf_index;
typedef uint32_t proton_cf_string_encoding;
typedef int32_t proton_cf_comparison_result;

typedef double (*proton_cg_event_source_seconds_since_last_type_t)(int32_t);

typedef proton_cf_type_ref (*proton_iops_copy_power_sources_info_fn)(void);
typedef proton_cf_array_ref (*proton_iops_copy_power_sources_list_fn)(
    proton_cf_type_ref);
typedef proton_cf_dictionary_ref (*proton_iops_get_power_source_description_fn)(
    proton_cf_type_ref, proton_cf_type_ref);
typedef void (*proton_cf_release_fn)(proton_cf_type_ref);
typedef proton_cf_index (*proton_cf_array_get_count_fn)(proton_cf_array_ref);
typedef proton_cf_type_ref (*proton_cf_array_get_value_at_index_fn)(
    proton_cf_array_ref, proton_cf_index);
typedef proton_cf_type_ref (*proton_cf_dictionary_get_value_fn)(
    proton_cf_dictionary_ref, const void *);
typedef void (*proton_cf_number_get_value_fn)(proton_cf_number_ref, uint32_t,
                                              void *);
typedef proton_cf_comparison_result (*proton_cf_string_compare_fn)(
    proton_cf_string_ref, proton_cf_string_ref, uint32_t);
typedef proton_cf_string_ref (*proton_cf_string_create_with_cstring_fn)(
    proton_cf_allocator_ref, const char *, proton_cf_string_encoding);

static proton_cg_event_source_seconds_since_last_type_t
    g_cg_event_source_seconds = NULL;
static int32_t g_cg_loaded = 0;

static struct {
  proton_cf_string_create_with_cstring_fn create_with_cstring;
  proton_cf_release_fn release;
  proton_cf_array_get_count_fn array_get_count;
  proton_cf_array_get_value_at_index_fn array_get_value_at_index;
  proton_cf_dictionary_get_value_fn dictionary_get_value;
  proton_cf_number_get_value_fn number_get_value;
  proton_cf_string_compare_fn string_compare;
  proton_iops_copy_power_sources_info_fn copy_power_sources_info;
  proton_iops_copy_power_sources_list_fn copy_power_sources_list;
  proton_iops_get_power_source_description_fn get_power_source_description;
  int32_t loaded;
  int32_t ready;
} g_mac;

static uint32_t const g_cfstring_utf8 = 0x08000100U;
static uint32_t const g_cfnumber_sint32 = 3;

static void power_monitor_load_cg(void) {
  if (g_cg_loaded) {
    return;
  }
  g_cg_loaded = 1;
  void *lib = dlopen(
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
    RTLD_NOW
  );
  if (lib == NULL) {
    return;
  }
  g_cg_event_source_seconds =
    (proton_cg_event_source_seconds_since_last_type_t)dlsym(
      lib,
      "CGEventSourceSecondsSinceLastEventType"
    );
}

static int32_t power_monitor_load_mac_symbols(void) {
  if (g_mac.loaded) {
    return g_mac.ready;
  }
  g_mac.loaded = 1;
  void *core_foundation = dlopen(
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    RTLD_LAZY | RTLD_LOCAL
  );
  void *iokit =
    dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
           RTLD_LAZY | RTLD_LOCAL);
  if (core_foundation == NULL || iokit == NULL) {
    if (core_foundation != NULL) {
      dlclose(core_foundation);
    }
    if (iokit != NULL) {
      dlclose(iokit);
    }
    return 0;
  }
  g_mac.create_with_cstring =
    (proton_cf_string_create_with_cstring_fn)dlsym(
      core_foundation, "CFStringCreateWithCString"
    );
  g_mac.release = (proton_cf_release_fn)dlsym(core_foundation, "CFRelease");
  g_mac.array_get_count =
    (proton_cf_array_get_count_fn)dlsym(core_foundation, "CFArrayGetCount");
  g_mac.array_get_value_at_index =
    (proton_cf_array_get_value_at_index_fn)dlsym(
      core_foundation, "CFArrayGetValueAtIndex"
    );
  g_mac.dictionary_get_value =
    (proton_cf_dictionary_get_value_fn)dlsym(
      core_foundation, "CFDictionaryGetValue"
    );
  g_mac.number_get_value = (proton_cf_number_get_value_fn)dlsym(
    core_foundation, "CFNumberGetValue"
  );
  g_mac.string_compare =
    (proton_cf_string_compare_fn)dlsym(core_foundation, "CFStringCompare");
  g_mac.copy_power_sources_info = (proton_iops_copy_power_sources_info_fn)
    dlsym(iokit, "IOPSCopyPowerSourcesInfo");
  g_mac.copy_power_sources_list = (proton_iops_copy_power_sources_list_fn)
    dlsym(iokit, "IOPSCopyPowerSourcesList");
  g_mac.get_power_source_description =
    (proton_iops_get_power_source_description_fn)dlsym(
      iokit, "IOPSGetPowerSourceDescription"
    );
  g_mac.ready =
    g_mac.create_with_cstring != NULL && g_mac.release != NULL &&
    g_mac.array_get_count != NULL && g_mac.array_get_value_at_index != NULL &&
    g_mac.dictionary_get_value != NULL && g_mac.number_get_value != NULL &&
    g_mac.string_compare != NULL && g_mac.copy_power_sources_info != NULL &&
    g_mac.copy_power_sources_list != NULL &&
    g_mac.get_power_source_description != NULL;
  return g_mac.ready;
}

void power_monitor_platform_init(power_monitor_state_t *state) {
  (void)state;
  power_monitor_load_cg();
}

int32_t power_monitor_platform_query_idle(power_monitor_state_t *state) {
  if (g_cg_event_source_seconds == NULL) {
    power_monitor_load_cg();
  }
  if (g_cg_event_source_seconds == NULL) {
    snprintf(state->last_error, sizeof(state->last_error),
             "CGEventSource is unavailable");
    return power_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  double seconds = g_cg_event_source_seconds(0);
  if (seconds < 0) {
    seconds = 0;
  }
  state->idle_seconds = (int64_t)seconds;
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_query_source(power_monitor_state_t *state) {
  state->source = power_monitor_SOURCE_UNKNOWN;
  state->has_battery_percent = 0;
  if (!power_monitor_load_mac_symbols()) {
    return power_monitor_STATUS_OK;
  }
  proton_cf_type_ref info = g_mac.copy_power_sources_info();
  if (info == NULL) {
    return power_monitor_STATUS_OK;
  }
  proton_cf_array_ref sources = g_mac.copy_power_sources_list(info);
  if (sources == NULL) {
    g_mac.release(info);
    return power_monitor_STATUS_OK;
  }

  proton_cf_string_ref state_key =
    g_mac.create_with_cstring(NULL, "Power Source State", g_cfstring_utf8);
  proton_cf_string_ref ac_value =
    g_mac.create_with_cstring(NULL, "AC Power", g_cfstring_utf8);
  proton_cf_string_ref battery_value =
    g_mac.create_with_cstring(NULL, "Battery Power", g_cfstring_utf8);
  proton_cf_string_ref current_key =
    g_mac.create_with_cstring(NULL, "Current Capacity", g_cfstring_utf8);
  proton_cf_string_ref max_key =
    g_mac.create_with_cstring(NULL, "Max Capacity", g_cfstring_utf8);

  proton_cf_index count = g_mac.array_get_count(sources);
  for (proton_cf_index i = 0; i < count; i++) {
    proton_cf_type_ref ps = g_mac.array_get_value_at_index(sources, i);
    proton_cf_dictionary_ref desc =
      g_mac.get_power_source_description(info, ps);
    if (desc == NULL) {
      continue;
    }
    proton_cf_type_ref type = g_mac.dictionary_get_value(desc, state_key);
    if (type != NULL) {
      if (g_mac.string_compare(type, ac_value, 0) == 0) {
        state->source = power_monitor_SOURCE_AC;
      } else if (g_mac.string_compare(type, battery_value, 0) == 0) {
        state->source = power_monitor_SOURCE_BATTERY;
      }
    }
    proton_cf_type_ref current =
      g_mac.dictionary_get_value(desc, current_key);
    proton_cf_type_ref max = g_mac.dictionary_get_value(desc, max_key);
    if (current != NULL && max != NULL) {
      int32_t cur_val = 0;
      int32_t max_val = 1;
      g_mac.number_get_value((proton_cf_number_ref)current,
                             g_cfnumber_sint32, &cur_val);
      g_mac.number_get_value((proton_cf_number_ref)max, g_cfnumber_sint32,
                             &max_val);
      if (max_val > 0) {
        state->battery_percent = (cur_val * 100) / max_val;
        state->has_battery_percent = 1;
      }
    }
    break;
  }
  if (state_key != NULL) {
    g_mac.release(state_key);
  }
  if (ac_value != NULL) {
    g_mac.release(ac_value);
  }
  if (battery_value != NULL) {
    g_mac.release(battery_value);
  }
  if (current_key != NULL) {
    g_mac.release(current_key);
  }
  if (max_key != NULL) {
    g_mac.release(max_key);
  }
  g_mac.release(sources);
  g_mac.release(info);
  return power_monitor_STATUS_OK;
}

/* --- Event watch backend ------------------------------------------------ */

typedef uint32_t proton_mach_port_t;
typedef uint32_t proton_natural_t;

typedef void (*proton_io_power_callback_fn)(
    void *refcon, proton_mach_port_t connection, proton_natural_t message_type,
    void *argument);

typedef proton_mach_port_t (*proton_io_register_system_power_fn)(
    void *refcon, void **notifier, void *notify_port,
    proton_io_power_callback_fn callback);
typedef proton_mach_port_t (*proton_io_deregister_system_power_fn)(
    proton_mach_port_t *root_port);
typedef proton_mach_port_t (*proton_io_allow_power_change_fn)(
    proton_mach_port_t root_port, intptr_t notification);
typedef void *(*proton_io_notification_port_create_fn)(
    proton_mach_port_t master_port);
typedef void (*proton_io_notification_port_destroy_fn)(void *notify_port);
typedef proton_cf_type_ref (*proton_io_notification_port_run_loop_source_fn)(
    void *notify_port);
typedef proton_cf_type_ref (*proton_iops_notification_run_loop_source_fn)(
    void (*callback)(void *context), void *context);

typedef proton_cf_type_ref (*proton_cf_run_loop_get_current_fn)(void);
typedef void (*proton_cf_run_loop_run_fn)(void);
typedef void (*proton_cf_run_loop_stop_fn)(proton_cf_type_ref);
typedef void (*proton_cf_run_loop_add_source_fn)(proton_cf_type_ref,
                                                 proton_cf_type_ref,
                                                 proton_cf_string_ref);
typedef void (*proton_cf_run_loop_remove_source_fn)(proton_cf_type_ref,
                                                    proton_cf_type_ref,
                                                    proton_cf_string_ref);
typedef void (*proton_cf_run_loop_source_invalidate_fn)(proton_cf_type_ref);

typedef uint32_t (*proton_notify_register_fn)(const char *name,
                                              int32_t *out_token,
                                              void (*callback)(int32_t token));
typedef uint32_t (*proton_notify_cancel_fn)(int32_t token);

#define k_power_monitor_system_will_sleep 0x1001u
#define k_power_monitor_system_has_powered_on 0x1003u

static struct {
  proton_io_register_system_power_fn io_register_system_power;
  proton_io_deregister_system_power_fn io_deregister_system_power;
  proton_io_allow_power_change_fn io_allow_power_change;
  proton_io_notification_port_create_fn io_notification_port_create;
  proton_io_notification_port_destroy_fn io_notification_port_destroy;
  proton_io_notification_port_run_loop_source_fn
      io_notification_port_run_loop_source;
  proton_iops_notification_run_loop_source_fn io_power_source_run_loop_source;
  proton_cf_run_loop_get_current_fn run_loop_get_current;
  proton_cf_run_loop_run_fn run_loop_run;
  proton_cf_run_loop_stop_fn run_loop_stop;
  proton_cf_run_loop_add_source_fn run_loop_add_source;
  proton_cf_run_loop_remove_source_fn run_loop_remove_source;
  proton_cf_run_loop_source_invalidate_fn run_loop_source_invalidate;
  proton_cf_release_fn release;
  proton_notify_register_fn notify_register;
  proton_notify_cancel_fn notify_cancel;
  int32_t loaded;
  int32_t ready;
} g_power_watch;

/* The notify(3) callbacks may fire on the main thread, so they reach the shared
   queue through a process-wide state pointer rather than a thread-local one. */
static power_monitor_state_t *g_notify_state = NULL;

static int32_t power_monitor_load_watch_symbols(void) {
  if (g_power_watch.loaded) {
    return g_power_watch.ready;
  }
  g_power_watch.loaded = 1;
  void *io_kit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                        RTLD_LAZY | RTLD_LOCAL);
  void *core_foundation = dlopen(
      "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
      RTLD_LAZY | RTLD_LOCAL);
  void *lib_system = dlopen("/usr/lib/libSystem.B.dylib",
                            RTLD_LAZY | RTLD_LOCAL);
  if (io_kit == NULL || core_foundation == NULL || lib_system == NULL) {
    if (io_kit != NULL) {
      dlclose(io_kit);
    }
    if (core_foundation != NULL) {
      dlclose(core_foundation);
    }
    if (lib_system != NULL) {
      dlclose(lib_system);
    }
    return 0;
  }
  g_power_watch.io_register_system_power =
      (proton_io_register_system_power_fn)dlsym(io_kit,
                                                "IORegisterForSystemPower");
  g_power_watch.io_deregister_system_power =
      (proton_io_deregister_system_power_fn)dlsym(
          io_kit, "IODeregisterForSystemPower");
  g_power_watch.io_allow_power_change =
      (proton_io_allow_power_change_fn)dlsym(io_kit, "IOAllowPowerChange");
  g_power_watch.io_notification_port_create =
      (proton_io_notification_port_create_fn)dlsym(io_kit,
                                                   "IONotificationPortCreate");
  g_power_watch.io_notification_port_destroy =
      (proton_io_notification_port_destroy_fn)dlsym(
          io_kit, "IONotificationPortDestroy");
  g_power_watch.io_notification_port_run_loop_source =
      (proton_io_notification_port_run_loop_source_fn)dlsym(
          io_kit, "IONotificationPortGetRunLoopSource");
  g_power_watch.io_power_source_run_loop_source =
      (proton_iops_notification_run_loop_source_fn)dlsym(
          io_kit, "IOPSNotificationCreateRunLoopSource");
  g_power_watch.run_loop_get_current =
      (proton_cf_run_loop_get_current_fn)dlsym(core_foundation,
                                               "CFRunLoopGetCurrent");
  g_power_watch.run_loop_run =
      (proton_cf_run_loop_run_fn)dlsym(core_foundation, "CFRunLoopRun");
  g_power_watch.run_loop_stop =
      (proton_cf_run_loop_stop_fn)dlsym(core_foundation, "CFRunLoopStop");
  g_power_watch.run_loop_add_source =
      (proton_cf_run_loop_add_source_fn)dlsym(core_foundation,
                                              "CFRunLoopAddSource");
  g_power_watch.run_loop_remove_source =
      (proton_cf_run_loop_remove_source_fn)dlsym(core_foundation,
                                                 "CFRunLoopRemoveSource");
  g_power_watch.run_loop_source_invalidate =
      (proton_cf_run_loop_source_invalidate_fn)dlsym(
          core_foundation, "CFRunLoopSourceInvalidate");
  g_power_watch.release = (proton_cf_release_fn)dlsym(core_foundation,
                                                      "CFRelease");
  g_power_watch.notify_register =
      (proton_notify_register_fn)dlsym(lib_system, "notify_register");
  g_power_watch.notify_cancel =
      (proton_notify_cancel_fn)dlsym(lib_system, "notify_cancel");
  g_power_watch.ready =
      g_power_watch.io_register_system_power != NULL &&
      g_power_watch.io_deregister_system_power != NULL &&
      g_power_watch.io_allow_power_change != NULL &&
      g_power_watch.io_notification_port_create != NULL &&
      g_power_watch.io_notification_port_destroy != NULL &&
      g_power_watch.io_notification_port_run_loop_source != NULL &&
      g_power_watch.io_power_source_run_loop_source != NULL &&
      g_power_watch.run_loop_get_current != NULL &&
      g_power_watch.run_loop_run != NULL &&
      g_power_watch.run_loop_stop != NULL &&
      g_power_watch.run_loop_add_source != NULL &&
      g_power_watch.run_loop_remove_source != NULL &&
      g_power_watch.run_loop_source_invalidate != NULL &&
      g_power_watch.release != NULL && g_power_watch.notify_register != NULL &&
      g_power_watch.notify_cancel != NULL;
  return g_power_watch.ready;
}

static void power_monitor_set_watch_error(power_monitor_state_t *state,
                                          const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

static void power_monitor_io_power_callback(void *refcon,
                                            proton_mach_port_t connection,
                                            proton_natural_t message_type,
                                            void *argument) {
  power_monitor_state_t *state = (power_monitor_state_t *)refcon;
  switch (message_type) {
    case k_power_monitor_system_will_sleep:
      power_monitor_push_event(state, power_monitor_EVENT_SUSPEND);
      if (g_power_watch.io_allow_power_change != NULL) {
        g_power_watch.io_allow_power_change(connection,
                                            (intptr_t)argument);
      }
      break;
    case k_power_monitor_system_has_powered_on:
      power_monitor_push_event(state, power_monitor_EVENT_RESUME);
      break;
    default:
      break;
  }
}

static void power_monitor_iops_source_callback(void *context) {
  power_monitor_state_t *state = (power_monitor_state_t *)context;
  if (!power_monitor_load_mac_symbols()) {
    return;
  }
  int32_t previous = state->last_source;
  if (power_monitor_platform_query_source(state) != power_monitor_STATUS_OK) {
    return;
  }
  if (previous == state->source) {
    return;
  }
  state->last_source = state->source;
  if (state->source == power_monitor_SOURCE_AC) {
    power_monitor_push_event(state, power_monitor_EVENT_ON_AC);
  } else if (state->source == power_monitor_SOURCE_BATTERY) {
    power_monitor_push_event(state, power_monitor_EVENT_ON_BATTERY);
  }
}

static void power_monitor_lock_notify(int32_t token) {
  (void)token;
  if (g_notify_state != NULL) {
    power_monitor_push_event(g_notify_state, power_monitor_EVENT_LOCK_SCREEN);
  }
}

static void power_monitor_unlock_notify(int32_t token) {
  (void)token;
  if (g_notify_state != NULL) {
    power_monitor_push_event(g_notify_state, power_monitor_EVENT_UNLOCK_SCREEN);
  }
}

static void *power_monitor_macos_watch_thread_main(void *param) {
  power_monitor_state_t *state = (power_monitor_state_t *)param;

  if (!power_monitor_load_watch_symbols()) {
    power_monitor_set_watch_error(state, "macOS watch symbols unavailable");
    pthread_mutex_lock(&state->event_lock);
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->event_lock);
    return NULL;
  }

  /* Seed the power source so only real changes are reported afterwards. */
  if (power_monitor_load_mac_symbols() &&
      power_monitor_platform_query_source(state) == power_monitor_STATUS_OK) {
    state->last_source = state->source;
  }

  proton_cf_type_ref run_loop = g_power_watch.run_loop_get_current();
  void *notify_port =
      g_power_watch.io_notification_port_create(0 /* kIOMasterPortDefault */);
  proton_cf_type_ref run_loop_source = NULL;
  proton_cf_type_ref power_source = NULL;
  if (notify_port != NULL) {
    run_loop_source =
        g_power_watch.io_notification_port_run_loop_source(notify_port);
    if (run_loop_source != NULL) {
      g_power_watch.run_loop_add_source(run_loop, run_loop_source, NULL);
    }
    uint32_t notifier = 0;
    uint32_t root_port = g_power_watch.io_register_system_power(
        state, (void **)&notifier, notify_port,
        power_monitor_io_power_callback);
    state->notify_port = notify_port;
    state->notify_ref = notifier;
    state->root_port = root_port;
    power_source = g_power_watch.io_power_source_run_loop_source(
        power_monitor_iops_source_callback, state);
    if (power_source != NULL) {
      g_power_watch.run_loop_add_source(run_loop, power_source, NULL);
    }
  }

  pthread_mutex_lock(&state->event_lock);
  state->run_loop = (void *)run_loop;
  state->observer_target = (void *)run_loop_source;
  state->power_source = (void *)power_source;
  state->watch_started = 1;
  state->ready = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->event_lock);

  /* Lock/unlock arrive through the notify(3) daemon, independent of the run
     loop; they may fire on the main thread, which is fine because push_event
     is thread-safe. */
  g_notify_state = state;
  g_power_watch.notify_register("com.apple.screenIsLocked", &state->lock_token,
                                power_monitor_lock_notify);
  g_power_watch.notify_register("com.apple.screenIsUnlocked",
                                &state->unlock_token,
                                power_monitor_unlock_notify);

  g_power_watch.run_loop_run();
  return NULL;
}

int32_t power_monitor_platform_start_watching(power_monitor_state_t *state) {
  if (state->thread_started) {
    return power_monitor_STATUS_OK;
  }
  if (!power_monitor_load_watch_symbols()) {
    power_monitor_set_watch_error(state, "macOS watch symbols unavailable");
    return power_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  pthread_mutex_lock(&state->event_lock);
  state->ready = 0;
  pthread_mutex_unlock(&state->event_lock);

  state->thread_started = 1;
  if (pthread_create(&state->watch_thread, NULL,
                     power_monitor_macos_watch_thread_main, state) != 0) {
    state->thread_started = 0;
    power_monitor_set_watch_error(state, "pthread_create failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }

  pthread_mutex_lock(&state->event_lock);
  while (!state->ready) {
    pthread_cond_wait(&state->ready_cond, &state->event_lock);
  }
  /* The thread signals ready in both the success and the failure path; only a
     started backend counts as OK, matching the documented best-effort
     contract (a failed backend reports BACKEND_UNAVAILABLE). */
  int32_t started = state->watch_started;
  pthread_mutex_unlock(&state->event_lock);
  return started ? power_monitor_STATUS_OK
                 : power_monitor_STATUS_BACKEND_UNAVAILABLE;
}

int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state) {
  g_notify_state = NULL;
  if (g_power_watch.notify_cancel != NULL) {
    if (state->lock_token != 0) {
      g_power_watch.notify_cancel(state->lock_token);
      state->lock_token = 0;
    }
    if (state->unlock_token != 0) {
      g_power_watch.notify_cancel(state->unlock_token);
      state->unlock_token = 0;
    }
  }

  if (state->thread_started) {
    if (state->run_loop != NULL) {
      g_power_watch.run_loop_stop((proton_cf_type_ref)state->run_loop);
    }
    pthread_join(state->watch_thread, NULL);
    state->watch_thread = 0;
    state->thread_started = 0;
  }

  if (state->notify_port != NULL) {
    g_power_watch.io_notification_port_destroy(state->notify_port);
    state->notify_port = NULL;
  }
  if (state->root_port != 0) {
    g_power_watch.io_deregister_system_power(&state->root_port);
    state->root_port = 0;
  }
  if (state->observer_target != NULL) {
    g_power_watch.run_loop_source_invalidate(
        (proton_cf_type_ref)state->observer_target);
    g_power_watch.release((proton_cf_type_ref)state->observer_target);
    state->observer_target = NULL;
  }
  if (state->power_source != NULL) {
    g_power_watch.run_loop_source_invalidate(
        (proton_cf_type_ref)state->power_source);
    g_power_watch.release((proton_cf_type_ref)state->power_source);
    state->power_source = NULL;
  }
  state->run_loop = NULL;
  state->watch_started = 0;
  return power_monitor_STATUS_OK;
}

#endif