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

#endif