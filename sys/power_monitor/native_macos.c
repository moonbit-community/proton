#include "native_stub.h"

#ifdef __APPLE__

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>

#include <dlfcn.h>
#include <stdio.h>

typedef double (*proton_cg_event_source_seconds_since_last_type_t)(int32_t);

static proton_cg_event_source_seconds_since_last_type_t
    g_cg_event_source_seconds = NULL;
static int32_t g_cg_loaded = 0;

static void power_monitor_load_cg(void) {
  if (g_cg_loaded) {
    return;
  }
  g_cg_loaded = 1;
  void *lib = dlopen(
      "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
      RTLD_NOW);
  if (lib == NULL) {
    return;
  }
  g_cg_event_source_seconds =
      (proton_cg_event_source_seconds_since_last_type_t)dlsym(
          lib, "CGEventSourceSecondsSinceLastEventType");
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
  CFTypeRef info = IOPSCopyPowerSourcesInfo();
  if (info == NULL) {
    state->source = power_monitor_SOURCE_UNKNOWN;
    state->has_battery_percent = 0;
    return power_monitor_STATUS_OK;
  }
  CFArrayRef sources = IOPSCopyPowerSourcesList(info);
  if (sources == NULL) {
    CFRelease(info);
    state->source = power_monitor_SOURCE_UNKNOWN;
    state->has_battery_percent = 0;
    return power_monitor_STATUS_OK;
  }
  state->source = power_monitor_SOURCE_UNKNOWN;
  state->has_battery_percent = 0;
  CFIndex count = CFArrayGetCount(sources);
  for (CFIndex i = 0; i < count; i++) {
    CFTypeRef ps = CFArrayGetValueAtIndex(sources, i);
    CFDictionaryRef desc = IOPSGetPowerSourceDescription(info, ps);
    if (desc == NULL) {
      continue;
    }
    CFStringRef type = (CFStringRef)CFDictionaryGetValue(
        desc, CFSTR(kIOPSPowerSourceStateKey));
    if (type != NULL) {
      if (CFStringCompare(type, CFSTR(kIOPSACPowerValue), 0) ==
          kCFCompareEqualTo) {
        state->source = power_monitor_SOURCE_AC;
      } else if (CFStringCompare(type, CFSTR(kIOPSBatteryPowerValue), 0) ==
                 kCFCompareEqualTo) {
        state->source = power_monitor_SOURCE_BATTERY;
      }
    }
    CFNumberRef current = (CFNumberRef)CFDictionaryGetValue(
        desc, CFSTR(kIOPSCurrentCapacityKey));
    CFNumberRef max = (CFNumberRef)CFDictionaryGetValue(
        desc, CFSTR(kIOPSMaxCapacityKey));
    if (current != NULL && max != NULL) {
      int32_t cur_val = 0;
      int32_t max_val = 1;
      CFNumberGetValue(current, kCFNumberSInt32Type, &cur_val);
      CFNumberGetValue(max, kCFNumberSInt32Type, &max_val);
      if (max_val > 0) {
        state->battery_percent = (cur_val * 100) / max_val;
        state->has_battery_percent = 1;
      }
    }
    break;
  }
  CFRelease(sources);
  CFRelease(info);
  return power_monitor_STATUS_OK;
}

#endif
