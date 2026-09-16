#include "native_stub.h"

#ifdef __APPLE__
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOMessage.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <dispatch/dispatch.h>
#include <notify.h>
#include <stdio.h>

void power_monitor_platform_init(power_monitor_state_t *state) {
  pthread_cond_init(&state->ready_cond, NULL);
  state->lock_token = -1;
  state->unlock_token = -1;
}

int32_t power_monitor_platform_query_idle(power_monitor_state_t *state) {
  double seconds = CGEventSourceSecondsSinceLastEventType(
      kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
  state->idle_seconds = seconds < 0 ? 0 : (int64_t)seconds;
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_query_source(power_monitor_state_t *state) {
  state->source = power_monitor_SOURCE_UNKNOWN;
  state->has_battery_percent = 0;
  CFTypeRef info = IOPSCopyPowerSourcesInfo();
  if (info == NULL) {
    return power_monitor_STATUS_OK;
  }
  CFArrayRef sources = IOPSCopyPowerSourcesList(info);
  if (sources == NULL) {
    CFRelease(info);
    return power_monitor_STATUS_OK;
  }

  CFStringRef state_key =
    CFStringCreateWithCString(NULL, "Power Source State", kCFStringEncodingUTF8);
  CFStringRef ac_value =
    CFStringCreateWithCString(NULL, "AC Power", kCFStringEncodingUTF8);
  CFStringRef battery_value =
    CFStringCreateWithCString(NULL, "Battery Power", kCFStringEncodingUTF8);
  CFStringRef current_key =
    CFStringCreateWithCString(NULL, "Current Capacity", kCFStringEncodingUTF8);
  CFStringRef max_key =
    CFStringCreateWithCString(NULL, "Max Capacity", kCFStringEncodingUTF8);

  CFIndex count = CFArrayGetCount(sources);
  for (CFIndex i = 0; i < count; i++) {
    CFTypeRef ps = CFArrayGetValueAtIndex(sources, i);
    CFDictionaryRef desc =
      IOPSGetPowerSourceDescription(info, ps);
    if (desc == NULL) {
      continue;
    }
    CFTypeRef type = CFDictionaryGetValue(desc, state_key);
    if (type != NULL) {
      if (CFStringCompare(type, ac_value, 0) == 0) {
        state->source = power_monitor_SOURCE_AC;
      } else if (CFStringCompare(type, battery_value, 0) == 0) {
        state->source = power_monitor_SOURCE_BATTERY;
      }
    }
    CFTypeRef current =
      CFDictionaryGetValue(desc, current_key);
    CFTypeRef max = CFDictionaryGetValue(desc, max_key);
    if (current != NULL && max != NULL) {
      int32_t cur_val = 0;
      int32_t max_val = 1;
      CFNumberGetValue((CFNumberRef)current,
                             kCFNumberSInt32Type, &cur_val);
      CFNumberGetValue((CFNumberRef)max, kCFNumberSInt32Type,
                             &max_val);
      if (max_val > 0) {
        state->battery_percent = (cur_val * 100) / max_val;
        state->has_battery_percent = 1;
      }
    }
    break;
  }
  if (state_key != NULL) {
    CFRelease(state_key);
  }
  if (ac_value != NULL) {
    CFRelease(ac_value);
  }
  if (battery_value != NULL) {
    CFRelease(battery_value);
  }
  if (current_key != NULL) {
    CFRelease(current_key);
  }
  if (max_key != NULL) {
    CFRelease(max_key);
  }
  CFRelease(sources);
  CFRelease(info);
  return power_monitor_STATUS_OK;
}

static void power_monitor_io_power_callback(void *context, io_service_t service,
                                            natural_t message, void *argument) {
  (void)service;
  power_monitor_state_t *state = context;
  switch (message) {
    case kIOMessageCanSystemSleep:
      IOAllowPowerChange(state->root_port, (intptr_t)argument);
      break;
    case kIOMessageSystemWillSleep:
      power_monitor_push_event(state, power_monitor_EVENT_SUSPEND);
      IOAllowPowerChange(state->root_port, (intptr_t)argument);
      break;
    case kIOMessageSystemHasPoweredOn:
      power_monitor_push_event(state, power_monitor_EVENT_RESUME);
      break;
  }
}

static void power_monitor_source_callback(void *context) {
  power_monitor_state_t *state = context;
  if (power_monitor_platform_query_source(state) != power_monitor_STATUS_OK ||
      state->last_source == state->source) {
    return;
  }
  state->last_source = state->source;
  if (state->source == power_monitor_SOURCE_AC) {
    power_monitor_push_event(state, power_monitor_EVENT_ON_AC);
  } else if (state->source == power_monitor_SOURCE_BATTERY) {
    power_monitor_push_event(state, power_monitor_EVENT_ON_BATTERY);
  }
}

/* Publish readiness only once the run loop is running, so an immediate stop
   cannot be lost before CFRunLoopRun enters the loop. */
static void power_monitor_watch_ready(CFRunLoopObserverRef observer,
                                      CFRunLoopActivity activity, void *context) {
  (void)observer;
  (void)activity;
  power_monitor_state_t *state = context;
  pthread_mutex_lock(&state->event_lock);
  state->watch_started = 1;
  state->ready = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->event_lock);
}

static void *power_monitor_watch_thread(void *context) {
  power_monitor_state_t *state = context;
  IONotificationPortRef port = NULL;
  state->root_port = IORegisterForSystemPower(
      state, &port, power_monitor_io_power_callback, &state->notify_ref);
  state->notify_port = port;
  if (state->root_port == IO_OBJECT_NULL) {
    goto failed;
  }
  CFRunLoopRef loop = CFRunLoopGetCurrent();
  CFRunLoopSourceRef source = IONotificationPortGetRunLoopSource(port);
  if (source == NULL) {
    goto failed;
  }
  CFRunLoopAddSource(loop, source, kCFRunLoopDefaultMode);
  power_monitor_platform_query_source(state);
  state->last_source = state->source;
  state->power_source = IOPSNotificationCreateRunLoopSource(
      power_monitor_source_callback, state);
  if (state->power_source == NULL) {
    goto failed;
  }
  CFRunLoopAddSource(loop, state->power_source, kCFRunLoopDefaultMode);
  dispatch_queue_t queue = dispatch_queue_create(
      "proton.power-monitor", DISPATCH_QUEUE_SERIAL);
  state->notify_queue = queue;
  if (queue == NULL ||
      notify_register_dispatch("com.apple.screenIsLocked", &state->lock_token,
          queue, ^(int token) {
            (void)token;
            power_monitor_push_event(state, power_monitor_EVENT_LOCK_SCREEN);
          }) != NOTIFY_STATUS_OK ||
      notify_register_dispatch("com.apple.screenIsUnlocked", &state->unlock_token,
          queue, ^(int token) {
            (void)token;
            power_monitor_push_event(state, power_monitor_EVENT_UNLOCK_SCREEN);
          }) != NOTIFY_STATUS_OK) {
    goto failed;
  }
  CFRunLoopObserverContext observer_context = {0, state, NULL, NULL, NULL};
  CFRunLoopObserverRef observer = CFRunLoopObserverCreate(
      NULL, kCFRunLoopEntry, false, 0, power_monitor_watch_ready, &observer_context);
  if (observer == NULL) {
    goto failed;
  }
  state->run_loop = loop;
  CFRunLoopAddObserver(loop, observer, kCFRunLoopDefaultMode);
  CFRunLoopRun();
  CFRunLoopObserverInvalidate(observer);
  CFRelease(observer);
  return NULL;

failed:
  snprintf(state->watch_error, sizeof(state->watch_error),
           "macOS power notification registration failed");
  pthread_mutex_lock(&state->event_lock);
  state->ready = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->event_lock);
  return NULL;
}

int32_t power_monitor_platform_start_watching(power_monitor_state_t *state) {
  if (state->thread_started) {
    return power_monitor_STATUS_OK;
  }
  state->ready = 0;
  state->watch_error[0] = '\0';
  if (pthread_create(&state->watch_thread, NULL,
                     power_monitor_watch_thread, state) != 0) {
    snprintf(state->watch_error, sizeof(state->watch_error), "pthread_create failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  state->thread_started = 1;
  pthread_mutex_lock(&state->event_lock);
  while (!state->ready) {
    pthread_cond_wait(&state->ready_cond, &state->event_lock);
  }
  int started = state->watch_started;
  pthread_mutex_unlock(&state->event_lock);
  if (!started) {
    snprintf(state->last_error, sizeof(state->last_error), "%s", state->watch_error);
    power_monitor_platform_stop_watching(state);
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state) {
  if (state->thread_started) {
    if (state->run_loop != NULL) {
      CFRunLoopStop(state->run_loop);
    }
    pthread_join(state->watch_thread, NULL);
    state->thread_started = 0;
  }
  if (state->lock_token != -1) {
    notify_cancel(state->lock_token);
    state->lock_token = -1;
  }
  if (state->unlock_token != -1) {
    notify_cancel(state->unlock_token);
    state->unlock_token = -1;
  }
  if (state->notify_queue != NULL) {
    /* Cancel first, then drain callbacks before the owner can release state. */
    dispatch_sync(state->notify_queue, ^{});
    dispatch_release(state->notify_queue);
    state->notify_queue = NULL;
  }
  if (state->notify_ref != IO_OBJECT_NULL) {
    IODeregisterForSystemPower(&state->notify_ref);
    state->notify_ref = IO_OBJECT_NULL;
  }
  if (state->notify_port != NULL) {
    IONotificationPortDestroy(state->notify_port);
    state->notify_port = NULL;
  }
  if (state->root_port != IO_OBJECT_NULL) {
    IOServiceClose(state->root_port);
    state->root_port = IO_OBJECT_NULL;
  }
  if (state->power_source != NULL) {
    CFRunLoopSourceInvalidate(state->power_source);
    CFRelease(state->power_source);
    state->power_source = NULL;
  }
  state->run_loop = NULL;
  state->watch_started = 0;
  return power_monitor_STATUS_OK;
}
#endif
