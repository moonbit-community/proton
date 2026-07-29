#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#ifdef _MSC_VER
#pragma comment(lib, "user32.lib")
#endif
#else
#include <dlfcn.h>
#include <pthread.h>
#endif

#ifdef __linux__
#include <sys/select.h>
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#endif

#ifdef __APPLE__
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>
#endif

#define MB_MOD_ALT 0x0001u
#define MB_MOD_CONTROL 0x0002u
#define MB_MOD_SHIFT 0x0004u
#define MB_MOD_META 0x0008u

#if defined(_MSC_VER)
#define MB_THREAD_LOCAL __declspec(thread)
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define MB_THREAD_LOCAL _Thread_local
#else
#define MB_THREAD_LOCAL
#endif

typedef struct mb_registration {
  int32_t id;
  uint32_t modifiers;
  uint32_t keycode;
  struct mb_registration *next;
} mb_registration_t;

typedef struct mb_trigger {
  int32_t id;
  struct mb_trigger *next;
} mb_trigger_t;

typedef struct mb_global_hotkey_state {
  mb_registration_t *registrations;
  mb_trigger_t *triggered_head;
  mb_trigger_t *triggered_tail;
  int32_t startup_status;
  char startup_error[512];
#ifdef _WIN32
  HANDLE thread;
  HANDLE ready_event;
  DWORD thread_id;
  CRITICAL_SECTION lock;
#elif defined(__linux__)
  pthread_t thread;
  pthread_mutex_t lock;
  pthread_cond_t ready_cond;
  int ready;
  int running;
  int thread_started;
  int wake_pipe[2];
  Display *display;
  Window root_window;
  unsigned int lock_mask;
  unsigned int numlock_mask;
#elif defined(__APPLE__)
  pthread_t thread;
  pthread_mutex_t lock;
  pthread_cond_t ready_cond;
  int ready;
  int running;
  int thread_started;
  CFMachPortRef event_tap;
  CFRunLoopRef run_loop;
#endif
} mb_global_hotkey_state_t;

static int mb_name_is_function_key(const char *name);
static int mb_keycode_from_name_common(
    const char *name,
    uint32_t *out_alpha_numeric);
static void mb_state_set_startup_error(
    mb_global_hotkey_state_t *state,
    const char *message);
static void mb_push_trigger_locked(
    mb_global_hotkey_state_t *state,
    int32_t id);

#ifdef __APPLE__
typedef struct mb_macos_api {
  void *app_services;
  void *core_foundation;
  int loaded;
  int initialized;
  CFMachPortRef (*CGEventTapCreate)(CGEventTapLocation, CGEventTapPlacement,
                                    CGEventTapOptions, CGEventMask,
                                    CGEventTapCallBack, void *);
  void (*CGEventTapEnable)(CFMachPortRef, bool);
  CGEventFlags (*CGEventGetFlags)(CGEventRef);
  int64_t (*CGEventGetIntegerValueField)(CGEventRef, CGEventField);
  CFRunLoopSourceRef (*CFMachPortCreateRunLoopSource)(CFAllocatorRef,
                                                      CFMachPortRef, CFIndex);
  CFRunLoopObserverRef (*CFRunLoopObserverCreate)(
      CFAllocatorRef,
      CFOptionFlags,
      Boolean,
      CFIndex,
      CFRunLoopObserverCallBack,
      CFRunLoopObserverContext *);
  CFRunLoopRef (*CFRunLoopGetCurrent)(void);
  void (*CFRunLoopAddSource)(CFRunLoopRef, CFRunLoopSourceRef, CFStringRef);
  void (*CFRunLoopAddObserver)(CFRunLoopRef, CFRunLoopObserverRef, CFStringRef);
  void (*CFRunLoopRun)(void);
  void (*CFRunLoopStop)(CFRunLoopRef);
  void (*CFRunLoopWakeUp)(CFRunLoopRef);
  CFTypeRef (*CFRetain)(CFTypeRef);
  void (*CFRelease)(CFTypeRef);
  CFStringRef (*CFStringCreateWithCString)(CFAllocatorRef, const char *,
                                          CFStringEncoding);
} mb_macos_api_t;

static mb_macos_api_t mb_macos_api;

static int mb_macos_load_api(void) {
  if (mb_macos_api.initialized) {
    return mb_macos_api.loaded;
  }

  memset(&mb_macos_api, 0, sizeof(mb_macos_api));
  mb_macos_api.initialized = 1;
  mb_macos_api.app_services = dlopen(
      "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
      RTLD_LAZY | RTLD_LOCAL);
  mb_macos_api.core_foundation = dlopen(
      "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
      RTLD_LAZY | RTLD_LOCAL);
  if (mb_macos_api.app_services == NULL || mb_macos_api.core_foundation == NULL) {
    return 0;
  }

  mb_macos_api.CGEventTapCreate =
      (CFMachPortRef(*)(CGEventTapLocation, CGEventTapPlacement,
                        CGEventTapOptions, CGEventMask, CGEventTapCallBack,
                        void *))dlsym(mb_macos_api.app_services, "CGEventTapCreate");
  mb_macos_api.CGEventTapEnable =
      (void (*)(CFMachPortRef, bool))dlsym(mb_macos_api.app_services, "CGEventTapEnable");
  mb_macos_api.CGEventGetFlags =
      (CGEventFlags(*)(CGEventRef))dlsym(mb_macos_api.app_services, "CGEventGetFlags");
  mb_macos_api.CGEventGetIntegerValueField =
      (int64_t(*)(CGEventRef, CGEventField))dlsym(
          mb_macos_api.app_services, "CGEventGetIntegerValueField");
  mb_macos_api.CFMachPortCreateRunLoopSource =
      (CFRunLoopSourceRef(*)(CFAllocatorRef, CFMachPortRef, CFIndex))dlsym(
          mb_macos_api.core_foundation, "CFMachPortCreateRunLoopSource");
  mb_macos_api.CFRunLoopObserverCreate =
      (CFRunLoopObserverRef(*)(CFAllocatorRef, CFOptionFlags, Boolean, CFIndex,
                               CFRunLoopObserverCallBack,
                               CFRunLoopObserverContext *))dlsym(
          mb_macos_api.core_foundation, "CFRunLoopObserverCreate");
  mb_macos_api.CFRunLoopGetCurrent =
      (CFRunLoopRef(*)(void))dlsym(mb_macos_api.core_foundation, "CFRunLoopGetCurrent");
  mb_macos_api.CFRunLoopAddSource =
      (void (*)(CFRunLoopRef, CFRunLoopSourceRef, CFStringRef))dlsym(
          mb_macos_api.core_foundation, "CFRunLoopAddSource");
  mb_macos_api.CFRunLoopAddObserver =
      (void (*)(CFRunLoopRef, CFRunLoopObserverRef, CFStringRef))dlsym(
          mb_macos_api.core_foundation, "CFRunLoopAddObserver");
  mb_macos_api.CFRunLoopRun =
      (void (*)(void))dlsym(mb_macos_api.core_foundation, "CFRunLoopRun");
  mb_macos_api.CFRunLoopStop =
      (void (*)(CFRunLoopRef))dlsym(mb_macos_api.core_foundation, "CFRunLoopStop");
  mb_macos_api.CFRunLoopWakeUp =
      (void (*)(CFRunLoopRef))dlsym(mb_macos_api.core_foundation, "CFRunLoopWakeUp");
  mb_macos_api.CFRetain =
      (CFTypeRef(*)(CFTypeRef))dlsym(mb_macos_api.core_foundation, "CFRetain");
  mb_macos_api.CFRelease =
      (void (*)(CFTypeRef))dlsym(mb_macos_api.core_foundation, "CFRelease");
  mb_macos_api.CFStringCreateWithCString =
      (CFStringRef(*)(CFAllocatorRef, const char *, CFStringEncoding))dlsym(
          mb_macos_api.core_foundation, "CFStringCreateWithCString");

  if (mb_macos_api.CGEventTapCreate == NULL ||
      mb_macos_api.CGEventTapEnable == NULL ||
      mb_macos_api.CGEventGetFlags == NULL ||
      mb_macos_api.CGEventGetIntegerValueField == NULL ||
      mb_macos_api.CFMachPortCreateRunLoopSource == NULL ||
      mb_macos_api.CFRunLoopObserverCreate == NULL ||
      mb_macos_api.CFRunLoopGetCurrent == NULL ||
      mb_macos_api.CFRunLoopAddSource == NULL ||
      mb_macos_api.CFRunLoopAddObserver == NULL ||
      mb_macos_api.CFRunLoopRun == NULL ||
      mb_macos_api.CFRunLoopStop == NULL ||
      mb_macos_api.CFRunLoopWakeUp == NULL ||
      mb_macos_api.CFRetain == NULL || mb_macos_api.CFRelease == NULL ||
      mb_macos_api.CFStringCreateWithCString == NULL) {
    return 0;
  }

  mb_macos_api.loaded = 1;
  return 1;
}

static uint32_t mb_macos_modifiers_from_flags(CGEventFlags flags) {
  uint32_t mask = 0;
  if ((flags & kCGEventFlagMaskAlternate) != 0) {
    mask |= MB_MOD_ALT;
  }
  if ((flags & kCGEventFlagMaskControl) != 0) {
    mask |= MB_MOD_CONTROL;
  }
  if ((flags & kCGEventFlagMaskShift) != 0) {
    mask |= MB_MOD_SHIFT;
  }
  if ((flags & kCGEventFlagMaskCommand) != 0) {
    mask |= MB_MOD_META;
  }
  return mask;
}

static int mb_macos_keycode_from_name(const char *name, uint32_t *out_keycode) {
  uint32_t alpha_numeric = 0;

  if (mb_keycode_from_name_common(name, &alpha_numeric)) {
    if (alpha_numeric >= 'A' && alpha_numeric <= 'Z') {
      *out_keycode = (uint32_t)(kVK_ANSI_A + (alpha_numeric - 'A'));
      return 1;
    }
    switch (alpha_numeric) {
    case '0':
      *out_keycode = kVK_ANSI_0;
      return 1;
    case '1':
      *out_keycode = kVK_ANSI_1;
      return 1;
    case '2':
      *out_keycode = kVK_ANSI_2;
      return 1;
    case '3':
      *out_keycode = kVK_ANSI_3;
      return 1;
    case '4':
      *out_keycode = kVK_ANSI_4;
      return 1;
    case '5':
      *out_keycode = kVK_ANSI_5;
      return 1;
    case '6':
      *out_keycode = kVK_ANSI_6;
      return 1;
    case '7':
      *out_keycode = kVK_ANSI_7;
      return 1;
    case '8':
      *out_keycode = kVK_ANSI_8;
      return 1;
    case '9':
      *out_keycode = kVK_ANSI_9;
      return 1;
    default:
      break;
    }
  }

  if (strcmp(name, "Space") == 0) {
    *out_keycode = kVK_Space;
    return 1;
  }
  if (strcmp(name, "Tab") == 0) {
    *out_keycode = kVK_Tab;
    return 1;
  }
  if (strcmp(name, "Enter") == 0) {
    *out_keycode = kVK_Return;
    return 1;
  }
  if (strcmp(name, "Escape") == 0) {
    *out_keycode = kVK_Escape;
    return 1;
  }
  if (strcmp(name, "Backspace") == 0) {
    *out_keycode = kVK_Delete;
    return 1;
  }
  if (strcmp(name, "Delete") == 0) {
    *out_keycode = kVK_ForwardDelete;
    return 1;
  }
  if (strcmp(name, "Home") == 0) {
    *out_keycode = kVK_Home;
    return 1;
  }
  if (strcmp(name, "End") == 0) {
    *out_keycode = kVK_End;
    return 1;
  }
  if (strcmp(name, "PageUp") == 0) {
    *out_keycode = kVK_PageUp;
    return 1;
  }
  if (strcmp(name, "PageDown") == 0) {
    *out_keycode = kVK_PageDown;
    return 1;
  }
  if (strcmp(name, "Left") == 0) {
    *out_keycode = kVK_LeftArrow;
    return 1;
  }
  if (strcmp(name, "Right") == 0) {
    *out_keycode = kVK_RightArrow;
    return 1;
  }
  if (strcmp(name, "Up") == 0) {
    *out_keycode = kVK_UpArrow;
    return 1;
  }
  if (strcmp(name, "Down") == 0) {
    *out_keycode = kVK_DownArrow;
    return 1;
  }
  if (strcmp(name, "Minus") == 0) {
    *out_keycode = kVK_ANSI_Minus;
    return 1;
  }
  if (strcmp(name, "Equal") == 0 || strcmp(name, "Plus") == 0) {
    *out_keycode = kVK_ANSI_Equal;
    return 1;
  }
  if (strcmp(name, "Comma") == 0) {
    *out_keycode = kVK_ANSI_Comma;
    return 1;
  }
  if (strcmp(name, "Period") == 0) {
    *out_keycode = kVK_ANSI_Period;
    return 1;
  }
  if (strcmp(name, "Slash") == 0) {
    *out_keycode = kVK_ANSI_Slash;
    return 1;
  }
  if (strcmp(name, "Backslash") == 0) {
    *out_keycode = kVK_ANSI_Backslash;
    return 1;
  }
  if (strcmp(name, "Semicolon") == 0) {
    *out_keycode = kVK_ANSI_Semicolon;
    return 1;
  }
  if (strcmp(name, "Quote") == 0) {
    *out_keycode = kVK_ANSI_Quote;
    return 1;
  }
  if (strcmp(name, "Backquote") == 0) {
    *out_keycode = kVK_ANSI_Grave;
    return 1;
  }
  if (strcmp(name, "LeftBracket") == 0) {
    *out_keycode = kVK_ANSI_LeftBracket;
    return 1;
  }
  if (strcmp(name, "RightBracket") == 0) {
    *out_keycode = kVK_ANSI_RightBracket;
    return 1;
  }
  if (mb_name_is_function_key(name)) {
    int number = atoi(name + 1);
    switch (number) {
    case 1:
      *out_keycode = kVK_F1;
      return 1;
    case 2:
      *out_keycode = kVK_F2;
      return 1;
    case 3:
      *out_keycode = kVK_F3;
      return 1;
    case 4:
      *out_keycode = kVK_F4;
      return 1;
    case 5:
      *out_keycode = kVK_F5;
      return 1;
    case 6:
      *out_keycode = kVK_F6;
      return 1;
    case 7:
      *out_keycode = kVK_F7;
      return 1;
    case 8:
      *out_keycode = kVK_F8;
      return 1;
    case 9:
      *out_keycode = kVK_F9;
      return 1;
    case 10:
      *out_keycode = kVK_F10;
      return 1;
    case 11:
      *out_keycode = kVK_F11;
      return 1;
    case 12:
      *out_keycode = kVK_F12;
      return 1;
    case 13:
      *out_keycode = kVK_F13;
      return 1;
    case 14:
      *out_keycode = kVK_F14;
      return 1;
    case 15:
      *out_keycode = kVK_F15;
      return 1;
    case 16:
      *out_keycode = kVK_F16;
      return 1;
    case 17:
      *out_keycode = kVK_F17;
      return 1;
    case 18:
      *out_keycode = kVK_F18;
      return 1;
    case 19:
      *out_keycode = kVK_F19;
      return 1;
    case 20:
      *out_keycode = kVK_F20;
      return 1;
    default:
      break;
    }
  }
  return 0;
}

static CGEventRef mb_macos_event_callback(CGEventTapProxy proxy,
                                          CGEventType type,
                                          CGEventRef event,
                                          void *user_info) {
  mb_global_hotkey_state_t *state = (mb_global_hotkey_state_t *)user_info;
  (void)proxy;

  if (type == kCGEventTapDisabledByTimeout ||
      type == kCGEventTapDisabledByUserInput) {
    if (state->event_tap != NULL) {
      mb_macos_api.CGEventTapEnable(state->event_tap, true);
    }
    return event;
  }

  if (type != kCGEventKeyDown) {
    return event;
  }

  if (mb_macos_api.CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0) {
    return event;
  }

  pthread_mutex_lock(&state->lock);
  {
    uint32_t keycode = (uint32_t)mb_macos_api.CGEventGetIntegerValueField(
        event, kCGKeyboardEventKeycode);
    uint32_t modifiers =
        mb_macos_modifiers_from_flags(mb_macos_api.CGEventGetFlags(event));
    mb_registration_t *cursor = state->registrations;
    while (cursor != NULL) {
      if (cursor->keycode == keycode && cursor->modifiers == modifiers) {
        mb_push_trigger_locked(state, cursor->id);
        break;
      }
      cursor = cursor->next;
    }
  }
  pthread_mutex_unlock(&state->lock);
  return event;
}

static void mb_macos_run_loop_ready_callback(CFRunLoopObserverRef observer,
                                             CFRunLoopActivity activity,
                                             void *user_info) {
  mb_global_hotkey_state_t *state = (mb_global_hotkey_state_t *)user_info;
  (void)observer;
  (void)activity;

  pthread_mutex_lock(&state->lock);
  state->ready = 1;
  state->running = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->lock);
}

static void *mb_macos_thread_main(void *raw_state) {
  mb_global_hotkey_state_t *state = (mb_global_hotkey_state_t *)raw_state;
  CFMachPortRef event_tap = NULL;
  CFRunLoopSourceRef source = NULL;
  CFRunLoopObserverRef startup_observer = NULL;
  CFRunLoopRef run_loop = NULL;
  CFStringRef mode = NULL;

  if (!mb_macos_load_api()) {
    pthread_mutex_lock(&state->lock);
    mb_state_set_startup_error(state, "failed to load macOS event frameworks");
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->lock);
    return NULL;
  }

  event_tap = mb_macos_api.CGEventTapCreate(
      kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
      (((CGEventMask)1) << kCGEventKeyDown) |
          (((CGEventMask)1) << kCGEventTapDisabledByTimeout) |
          (((CGEventMask)1) << kCGEventTapDisabledByUserInput),
      mb_macos_event_callback, state);
  if (event_tap == NULL) {
    pthread_mutex_lock(&state->lock);
    mb_state_set_startup_error(
        state,
        "failed to create a macOS event tap; grant Input Monitoring permission if needed");
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->lock);
    return NULL;
  }

  source = mb_macos_api.CFMachPortCreateRunLoopSource(NULL, event_tap, 0);
  if (source == NULL) {
    pthread_mutex_lock(&state->lock);
    mb_state_set_startup_error(state, "failed to create the macOS run loop source");
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->lock);
    mb_macos_api.CFRelease(event_tap);
    return NULL;
  }

  mode = mb_macos_api.CFStringCreateWithCString(NULL, "kCFRunLoopDefaultMode",
                                                kCFStringEncodingUTF8);
  if (mode == NULL) {
    pthread_mutex_lock(&state->lock);
    mb_state_set_startup_error(state, "failed to create the macOS run loop mode");
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->lock);
    mb_macos_api.CFRelease(source);
    mb_macos_api.CFRelease(event_tap);
    return NULL;
  }

  run_loop = mb_macos_api.CFRunLoopGetCurrent();
  mb_macos_api.CFRetain(run_loop);

  {
    CFRunLoopObserverContext observer_context = {0, state, NULL, NULL, NULL};
    startup_observer = mb_macos_api.CFRunLoopObserverCreate(
        NULL, kCFRunLoopEntry, false, 0, mb_macos_run_loop_ready_callback,
        &observer_context);
  }
  if (startup_observer == NULL) {
    pthread_mutex_lock(&state->lock);
    mb_state_set_startup_error(state, "failed to create the macOS run loop observer");
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->lock);
    mb_macos_api.CFRelease(run_loop);
    mb_macos_api.CFRelease(mode);
    mb_macos_api.CFRelease(source);
    mb_macos_api.CFRelease(event_tap);
    return NULL;
  }

  pthread_mutex_lock(&state->lock);
  state->event_tap = event_tap;
  state->run_loop = run_loop;
  pthread_mutex_unlock(&state->lock);

  mb_macos_api.CFRunLoopAddSource(run_loop, source, mode);
  mb_macos_api.CFRunLoopAddObserver(run_loop, startup_observer, mode);
  mb_macos_api.CGEventTapEnable(event_tap, true);
  mb_macos_api.CFRelease(startup_observer);
  startup_observer = NULL;
  mb_macos_api.CFRelease(source);
  mb_macos_api.CFRunLoopRun();

  pthread_mutex_lock(&state->lock);
  state->running = 0;
  state->event_tap = NULL;
  state->run_loop = NULL;
  pthread_mutex_unlock(&state->lock);

  mb_macos_api.CFRelease(mode);
  mb_macos_api.CFRelease(run_loop);
  mb_macos_api.CFRelease(event_tap);
  return NULL;
}
#endif

#ifdef __linux__
typedef struct mb_x11_api {
  void *handle;
  int loaded;
  int initialized;
  Status (*XInitThreads)(void);
  Display *(*XOpenDisplay)(const char *);
  int (*XCloseDisplay)(Display *);
  int (*XPending)(Display *);
  int (*XNextEvent)(Display *, XEvent *);
  int (*XGrabKey)(Display *, int, unsigned int, Window, Bool, int, int);
  int (*XUngrabKey)(Display *, int, unsigned int, Window);
  int (*XFlush)(Display *);
  int (*XSync)(Display *, Bool);
  KeySym (*XStringToKeysym)(const char *);
  KeyCode (*XKeysymToKeycode)(Display *, KeySym);
  int (*XSetErrorHandler)(int (*handler)(Display *, XErrorEvent *));
  XModifierKeymap *(*XGetModifierMapping)(Display *);
  int (*XFreeModifiermap)(XModifierKeymap *);
} mb_x11_api_t;

static mb_x11_api_t mb_x11_api;
static MB_THREAD_LOCAL int mb_linux_x11_error_code = 0;

static int mb_linux_x11_error_handler(Display *display, XErrorEvent *event) {
  (void)display;
  mb_linux_x11_error_code = event->error_code;
  return 0;
}

static int mb_linux_load_x11(void) {
  if (mb_x11_api.initialized) {
    return mb_x11_api.loaded;
  }

  memset(&mb_x11_api, 0, sizeof(mb_x11_api));
  mb_x11_api.initialized = 1;
  mb_x11_api.handle = dlopen("libX11.so.6", RTLD_LAZY | RTLD_LOCAL);
  if (mb_x11_api.handle == NULL) {
    mb_x11_api.handle = dlopen("libX11.so", RTLD_LAZY | RTLD_LOCAL);
  }
  if (mb_x11_api.handle == NULL) {
    return 0;
  }

  mb_x11_api.XInitThreads =
      (Status(*)(void))dlsym(mb_x11_api.handle, "XInitThreads");
  mb_x11_api.XOpenDisplay =
      (Display * (*)(const char *))dlsym(mb_x11_api.handle, "XOpenDisplay");
  mb_x11_api.XCloseDisplay =
      (int (*)(Display *))dlsym(mb_x11_api.handle, "XCloseDisplay");
  mb_x11_api.XPending =
      (int (*)(Display *))dlsym(mb_x11_api.handle, "XPending");
  mb_x11_api.XNextEvent =
      (int (*)(Display *, XEvent *))dlsym(mb_x11_api.handle, "XNextEvent");
  mb_x11_api.XGrabKey = (int (*)(Display *, int, unsigned int, Window, Bool,
                                  int, int))dlsym(mb_x11_api.handle, "XGrabKey");
  mb_x11_api.XUngrabKey = (int (*)(Display *, int, unsigned int, Window))
      dlsym(mb_x11_api.handle, "XUngrabKey");
  mb_x11_api.XFlush =
      (int (*)(Display *))dlsym(mb_x11_api.handle, "XFlush");
  mb_x11_api.XSync =
      (int (*)(Display *, Bool))dlsym(mb_x11_api.handle, "XSync");
  mb_x11_api.XStringToKeysym = (KeySym(*)(const char *))
      dlsym(mb_x11_api.handle, "XStringToKeysym");
  mb_x11_api.XKeysymToKeycode = (KeyCode(*)(Display *, KeySym))
      dlsym(mb_x11_api.handle, "XKeysymToKeycode");
  mb_x11_api.XSetErrorHandler = (int (*)(int (*)(Display *, XErrorEvent *)))
      dlsym(mb_x11_api.handle, "XSetErrorHandler");
  mb_x11_api.XGetModifierMapping = (XModifierKeymap * (*)(Display *))
      dlsym(mb_x11_api.handle, "XGetModifierMapping");
  mb_x11_api.XFreeModifiermap = (int (*)(XModifierKeymap *))
      dlsym(mb_x11_api.handle, "XFreeModifiermap");

  if (mb_x11_api.XInitThreads == NULL || mb_x11_api.XOpenDisplay == NULL ||
      mb_x11_api.XCloseDisplay == NULL || mb_x11_api.XPending == NULL ||
      mb_x11_api.XNextEvent == NULL || mb_x11_api.XGrabKey == NULL ||
      mb_x11_api.XUngrabKey == NULL || mb_x11_api.XFlush == NULL ||
      mb_x11_api.XSync == NULL || mb_x11_api.XStringToKeysym == NULL ||
      mb_x11_api.XKeysymToKeycode == NULL ||
      mb_x11_api.XSetErrorHandler == NULL ||
      mb_x11_api.XGetModifierMapping == NULL ||
      mb_x11_api.XFreeModifiermap == NULL) {
    dlclose(mb_x11_api.handle);
    memset(&mb_x11_api, 0, sizeof(mb_x11_api));
    mb_x11_api.initialized = 1;
    return 0;
  }

  if (mb_x11_api.XInitThreads() == 0) {
    dlclose(mb_x11_api.handle);
    memset(&mb_x11_api, 0, sizeof(mb_x11_api));
    mb_x11_api.initialized = 1;
    return 0;
  }

  mb_x11_api.loaded = 1;
  return 1;
}

static unsigned int mb_linux_modifiers(uint32_t modifiers) {
  unsigned int mask = 0;
  if ((modifiers & MB_MOD_ALT) != 0) {
    mask |= Mod1Mask;
  }
  if ((modifiers & MB_MOD_CONTROL) != 0) {
    mask |= ControlMask;
  }
  if ((modifiers & MB_MOD_SHIFT) != 0) {
    mask |= ShiftMask;
  }
  if ((modifiers & MB_MOD_META) != 0) {
    mask |= Mod4Mask;
  }
  return mask;
}

static unsigned int mb_linux_clean_event_modifiers(
    mb_global_hotkey_state_t *state,
    unsigned int modifiers) {
  unsigned int clean = modifiers;
  clean &= ~(state->lock_mask | state->numlock_mask);
  clean &= (ShiftMask | ControlMask | Mod1Mask | Mod4Mask);
  return clean;
}

static unsigned int mb_linux_detect_numlock_mask(Display *display) {
  unsigned int mask = 0;
  XModifierKeymap *modifier_map = mb_x11_api.XGetModifierMapping(display);
  KeyCode numlock_keycode;
  int modifier_index;
  int key_index;

  if (modifier_map == NULL) {
    return 0;
  }

  numlock_keycode = mb_x11_api.XKeysymToKeycode(display, XK_Num_Lock);
  for (modifier_index = 0; modifier_index < 8; modifier_index++) {
    for (key_index = 0; key_index < modifier_map->max_keypermod; key_index++) {
      KeyCode keycode =
          modifier_map->modifiermap[modifier_index * modifier_map->max_keypermod +
                                    key_index];
      if (keycode == numlock_keycode) {
        mask = (unsigned int)(1u << modifier_index);
        break;
      }
    }
    if (mask != 0) {
      break;
    }
  }

  mb_x11_api.XFreeModifiermap(modifier_map);
  return mask;
}

static const char *mb_linux_keysym_name(const char *name) {
  if (strcmp(name, "Space") == 0) {
    return "space";
  }
  if (strcmp(name, "Tab") == 0) {
    return "Tab";
  }
  if (strcmp(name, "Enter") == 0) {
    return "Return";
  }
  if (strcmp(name, "Escape") == 0) {
    return "Escape";
  }
  if (strcmp(name, "Backspace") == 0) {
    return "BackSpace";
  }
  if (strcmp(name, "Delete") == 0) {
    return "Delete";
  }
  if (strcmp(name, "Insert") == 0) {
    return "Insert";
  }
  if (strcmp(name, "Home") == 0) {
    return "Home";
  }
  if (strcmp(name, "End") == 0) {
    return "End";
  }
  if (strcmp(name, "PageUp") == 0) {
    return "Page_Up";
  }
  if (strcmp(name, "PageDown") == 0) {
    return "Page_Down";
  }
  if (strcmp(name, "Left") == 0) {
    return "Left";
  }
  if (strcmp(name, "Right") == 0) {
    return "Right";
  }
  if (strcmp(name, "Up") == 0) {
    return "Up";
  }
  if (strcmp(name, "Down") == 0) {
    return "Down";
  }
  if (strcmp(name, "Minus") == 0) {
    return "minus";
  }
  if (strcmp(name, "Equal") == 0) {
    return "equal";
  }
  if (strcmp(name, "Plus") == 0) {
    return "plus";
  }
  if (strcmp(name, "Comma") == 0) {
    return "comma";
  }
  if (strcmp(name, "Period") == 0) {
    return "period";
  }
  if (strcmp(name, "Slash") == 0) {
    return "slash";
  }
  if (strcmp(name, "Backslash") == 0) {
    return "backslash";
  }
  if (strcmp(name, "Semicolon") == 0) {
    return "semicolon";
  }
  if (strcmp(name, "Quote") == 0) {
    return "apostrophe";
  }
  if (strcmp(name, "Backquote") == 0) {
    return "grave";
  }
  if (strcmp(name, "LeftBracket") == 0) {
    return "bracketleft";
  }
  if (strcmp(name, "RightBracket") == 0) {
    return "bracketright";
  }
  return name;
}

static int mb_linux_keycode_from_name(
    Display *display,
    const char *name,
    KeyCode *out_keycode) {
  uint32_t alpha_numeric = 0;
  const char *keysym_name;
  KeySym keysym;

  if (mb_keycode_from_name_common(name, &alpha_numeric)) {
    keysym = mb_x11_api.XStringToKeysym(name);
    if (keysym == NoSymbol) {
      return 0;
    }
    *out_keycode = mb_x11_api.XKeysymToKeycode(display, keysym);
    return *out_keycode != 0;
  }

  keysym_name = mb_linux_keysym_name(name);
  keysym = mb_x11_api.XStringToKeysym(keysym_name);
  if (keysym == NoSymbol) {
    return 0;
  }
  *out_keycode = mb_x11_api.XKeysymToKeycode(display, keysym);
  return *out_keycode != 0;
}

static void *mb_linux_thread_main(void *raw_state) {
  mb_global_hotkey_state_t *state = (mb_global_hotkey_state_t *)raw_state;
  int display_fd = ConnectionNumber(state->display);

  pthread_mutex_lock(&state->lock);
  state->ready = 1;
  state->running = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->lock);

  while (1) {
    fd_set read_fds;
    int max_fd = display_fd > state->wake_pipe[0] ? display_fd : state->wake_pipe[0];
    int select_result;

    FD_ZERO(&read_fds);
    FD_SET(display_fd, &read_fds);
    FD_SET(state->wake_pipe[0], &read_fds);

    select_result = select(max_fd + 1, &read_fds, NULL, NULL, NULL);
    if (select_result <= 0) {
      continue;
    }

    if (FD_ISSET(state->wake_pipe[0], &read_fds)) {
      char byte = 0;
      (void)read(state->wake_pipe[0], &byte, 1);
      pthread_mutex_lock(&state->lock);
      if (!state->running) {
        pthread_mutex_unlock(&state->lock);
        break;
      }
      pthread_mutex_unlock(&state->lock);
    }

    if (FD_ISSET(display_fd, &read_fds)) {
      while (mb_x11_api.XPending(state->display) > 0) {
        XEvent event;
        mb_x11_api.XNextEvent(state->display, &event);
        if (event.type == KeyPress) {
          unsigned int clean_modifiers =
              mb_linux_clean_event_modifiers(state, event.xkey.state);
          pthread_mutex_lock(&state->lock);
          {
            mb_registration_t *cursor = state->registrations;
            while (cursor != NULL) {
              if (cursor->keycode == (uint32_t)event.xkey.keycode &&
                  cursor->modifiers == clean_modifiers) {
                mb_push_trigger_locked(state, cursor->id);
                break;
              }
              cursor = cursor->next;
            }
          }
          pthread_mutex_unlock(&state->lock);
        }
      }
    }
  }

  pthread_mutex_lock(&state->lock);
  state->running = 0;
  pthread_mutex_unlock(&state->lock);
  return NULL;
}
#endif

static MB_THREAD_LOCAL char mb_last_error_message[512] = "";

static void mb_set_error_message(const char *message) {
  if (message == NULL) {
    mb_last_error_message[0] = '\0';
    return;
  }
  snprintf(mb_last_error_message, sizeof(mb_last_error_message), "%s", message);
}

static moonbit_bytes_t mb_make_bytes_from_buffer(const char *buffer, size_t len) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(out, buffer, len);
  }
  return out;
}

static char *mb_copy_bytes_to_c_string(moonbit_bytes_t bytes) {
  size_t len = (size_t)Moonbit_array_length(bytes);
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (len > 0) {
    memcpy(copy, bytes, len);
  }
  copy[len] = '\0';
  return copy;
}

#if defined(__linux__) || defined(__APPLE__)
static int mb_init_sync_primitives(
    pthread_mutex_t *lock,
    pthread_cond_t *ready_cond) {
  if (pthread_mutex_init(lock, NULL) != 0) {
    return 0;
  }
  if (pthread_cond_init(ready_cond, NULL) != 0) {
    pthread_mutex_destroy(lock);
    return 0;
  }
  return 1;
}

static void mb_destroy_sync_primitives(
    pthread_mutex_t *lock,
    pthread_cond_t *ready_cond) {
  pthread_cond_destroy(ready_cond);
  pthread_mutex_destroy(lock);
}
#endif

static void mb_state_set_startup_error(
    mb_global_hotkey_state_t *state,
    const char *message) {
  state->startup_status = 1;
  snprintf(state->startup_error, sizeof(state->startup_error), "%s",
           message == NULL ? "" : message);
}

static void mb_free_registrations(mb_registration_t *registration) {
  while (registration != NULL) {
    mb_registration_t *next = registration->next;
    free(registration);
    registration = next;
  }
}

static void mb_free_triggers(mb_trigger_t *trigger) {
  while (trigger != NULL) {
    mb_trigger_t *next = trigger->next;
    free(trigger);
    trigger = next;
  }
}

static void mb_clear_runtime_state_locked(mb_global_hotkey_state_t *state) {
  mb_free_registrations(state->registrations);
  mb_free_triggers(state->triggered_head);
  state->registrations = NULL;
  state->triggered_head = NULL;
  state->triggered_tail = NULL;
}

static void mb_push_trigger_locked(
    mb_global_hotkey_state_t *state,
    int32_t id) {
  mb_trigger_t *node = (mb_trigger_t *)calloc(1, sizeof(*node));
  if (node == NULL) {
    return;
  }
  node->id = id;
  if (state->triggered_tail == NULL) {
    state->triggered_head = node;
    state->triggered_tail = node;
  } else {
    state->triggered_tail->next = node;
    state->triggered_tail = node;
  }
}

static int32_t mb_take_triggered_id_locked(mb_global_hotkey_state_t *state) {
  int32_t id = 0;
  mb_trigger_t *node = state->triggered_head;
  if (node == NULL) {
    return 0;
  }
  id = node->id;
  state->triggered_head = node->next;
  if (state->triggered_head == NULL) {
    state->triggered_tail = NULL;
  }
  free(node);
  return id;
}

static mb_registration_t *mb_find_registration_locked(
    mb_global_hotkey_state_t *state,
    int32_t id) {
  mb_registration_t *cursor = state->registrations;
  while (cursor != NULL) {
    if (cursor->id == id) {
      return cursor;
    }
    cursor = cursor->next;
  }
  return NULL;
}

static void mb_add_registration_locked(
    mb_global_hotkey_state_t *state,
    int32_t id,
    uint32_t modifiers,
    uint32_t keycode) {
  mb_registration_t *node = (mb_registration_t *)calloc(1, sizeof(*node));
  if (node == NULL) {
    return;
  }
  node->id = id;
  node->modifiers = modifiers;
  node->keycode = keycode;
  node->next = state->registrations;
  state->registrations = node;
}

static int mb_remove_registration_locked(
    mb_global_hotkey_state_t *state,
    int32_t id,
    uint32_t *out_modifiers,
    uint32_t *out_keycode) {
  mb_registration_t *cursor = state->registrations;
  mb_registration_t *previous = NULL;
  while (cursor != NULL) {
    if (cursor->id == id) {
      if (out_modifiers != NULL) {
        *out_modifiers = cursor->modifiers;
      }
      if (out_keycode != NULL) {
        *out_keycode = cursor->keycode;
      }
      if (previous == NULL) {
        state->registrations = cursor->next;
      } else {
        previous->next = cursor->next;
      }
      free(cursor);
      return 1;
    }
    previous = cursor;
    cursor = cursor->next;
  }
  return 0;
}

static int mb_name_is_function_key(const char *name) {
  return name[0] == 'F' && name[1] >= '1' && name[1] <= '9';
}

static int mb_keycode_from_name_common(
    const char *name,
    uint32_t *out_alpha_numeric) {
  size_t len = strlen(name);
  if (len == 1) {
    unsigned char ch = (unsigned char)name[0];
    if ((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
      *out_alpha_numeric = (uint32_t)ch;
      return 1;
    }
  }
  return 0;
}

#ifdef _WIN32
#define MB_WIN_MSG_REGISTER (WM_APP + 401)
#define MB_WIN_MSG_UNREGISTER (WM_APP + 402)
#define MB_WIN_MSG_QUIT (WM_APP + 403)

typedef struct mb_win_command {
  HANDLE done_event;
  int32_t status;
  int32_t id;
  UINT modifiers;
  UINT keycode;
} mb_win_command_t;

static UINT mb_windows_modifiers(uint32_t modifiers) {
  UINT mask = 0;
  if ((modifiers & MB_MOD_ALT) != 0) {
    mask |= MOD_ALT;
  }
  if ((modifiers & MB_MOD_CONTROL) != 0) {
    mask |= MOD_CONTROL;
  }
  if ((modifiers & MB_MOD_SHIFT) != 0) {
    mask |= MOD_SHIFT;
  }
  if ((modifiers & MB_MOD_META) != 0) {
    mask |= MOD_WIN;
  }
  return mask;
}

static int mb_windows_keycode_from_name(const char *name, UINT *out_keycode) {
  uint32_t alpha_numeric = 0;
  if (mb_keycode_from_name_common(name, &alpha_numeric)) {
    *out_keycode = (UINT)alpha_numeric;
    return 1;
  }

  if (strcmp(name, "Space") == 0) {
    *out_keycode = VK_SPACE;
    return 1;
  }
  if (strcmp(name, "Tab") == 0) {
    *out_keycode = VK_TAB;
    return 1;
  }
  if (strcmp(name, "Enter") == 0) {
    *out_keycode = VK_RETURN;
    return 1;
  }
  if (strcmp(name, "Escape") == 0) {
    *out_keycode = VK_ESCAPE;
    return 1;
  }
  if (strcmp(name, "Backspace") == 0) {
    *out_keycode = VK_BACK;
    return 1;
  }
  if (strcmp(name, "Delete") == 0) {
    *out_keycode = VK_DELETE;
    return 1;
  }
  if (strcmp(name, "Insert") == 0) {
    *out_keycode = VK_INSERT;
    return 1;
  }
  if (strcmp(name, "Home") == 0) {
    *out_keycode = VK_HOME;
    return 1;
  }
  if (strcmp(name, "End") == 0) {
    *out_keycode = VK_END;
    return 1;
  }
  if (strcmp(name, "PageUp") == 0) {
    *out_keycode = VK_PRIOR;
    return 1;
  }
  if (strcmp(name, "PageDown") == 0) {
    *out_keycode = VK_NEXT;
    return 1;
  }
  if (strcmp(name, "Left") == 0) {
    *out_keycode = VK_LEFT;
    return 1;
  }
  if (strcmp(name, "Right") == 0) {
    *out_keycode = VK_RIGHT;
    return 1;
  }
  if (strcmp(name, "Up") == 0) {
    *out_keycode = VK_UP;
    return 1;
  }
  if (strcmp(name, "Down") == 0) {
    *out_keycode = VK_DOWN;
    return 1;
  }
  if (strcmp(name, "Minus") == 0) {
    *out_keycode = VK_OEM_MINUS;
    return 1;
  }
  if (strcmp(name, "Equal") == 0 || strcmp(name, "Plus") == 0) {
    *out_keycode = VK_OEM_PLUS;
    return 1;
  }
  if (strcmp(name, "Comma") == 0) {
    *out_keycode = VK_OEM_COMMA;
    return 1;
  }
  if (strcmp(name, "Period") == 0) {
    *out_keycode = VK_OEM_PERIOD;
    return 1;
  }
  if (strcmp(name, "Slash") == 0) {
    *out_keycode = VK_OEM_2;
    return 1;
  }
  if (strcmp(name, "Backslash") == 0) {
    *out_keycode = VK_OEM_5;
    return 1;
  }
  if (strcmp(name, "Semicolon") == 0) {
    *out_keycode = VK_OEM_1;
    return 1;
  }
  if (strcmp(name, "Quote") == 0) {
    *out_keycode = VK_OEM_7;
    return 1;
  }
  if (strcmp(name, "Backquote") == 0) {
    *out_keycode = VK_OEM_3;
    return 1;
  }
  if (strcmp(name, "LeftBracket") == 0) {
    *out_keycode = VK_OEM_4;
    return 1;
  }
  if (strcmp(name, "RightBracket") == 0) {
    *out_keycode = VK_OEM_6;
    return 1;
  }
  if (mb_name_is_function_key(name)) {
    int number = atoi(name + 1);
    if (number >= 1 && number <= 24) {
      *out_keycode = (UINT)(VK_F1 + (number - 1));
      return 1;
    }
  }
  return 0;
}

static DWORD WINAPI mb_windows_thread_main(void *raw_state) {
  MSG message;
  mb_global_hotkey_state_t *state = (mb_global_hotkey_state_t *)raw_state;

  PeekMessage(&message, NULL, WM_USER, WM_USER, PM_NOREMOVE);
  SetEvent(state->ready_event);

  while (GetMessage(&message, NULL, 0, 0) > 0) {
    if (message.message == MB_WIN_MSG_REGISTER) {
      mb_win_command_t *command = (mb_win_command_t *)message.lParam;
      if (RegisterHotKey(NULL, command->id, command->modifiers, command->keycode)) {
        EnterCriticalSection(&state->lock);
        mb_add_registration_locked(state, command->id, 0, 0);
        LeaveCriticalSection(&state->lock);
        command->status = 0;
      } else {
        command->status = 1;
      }
      SetEvent(command->done_event);
      continue;
    }

    if (message.message == MB_WIN_MSG_UNREGISTER) {
      mb_win_command_t *command = (mb_win_command_t *)message.lParam;
      if (UnregisterHotKey(NULL, command->id)) {
        EnterCriticalSection(&state->lock);
        mb_remove_registration_locked(state, command->id, NULL, NULL);
        LeaveCriticalSection(&state->lock);
        command->status = 0;
      } else {
        command->status = 1;
      }
      SetEvent(command->done_event);
      continue;
    }

    if (message.message == MB_WIN_MSG_QUIT) {
      PostQuitMessage(0);
      continue;
    }

    if (message.message == WM_HOTKEY) {
      EnterCriticalSection(&state->lock);
      mb_push_trigger_locked(state, (int32_t)message.wParam);
      LeaveCriticalSection(&state->lock);
    }
  }

  EnterCriticalSection(&state->lock);
  {
    mb_registration_t *cursor = state->registrations;
    while (cursor != NULL) {
      UnregisterHotKey(NULL, cursor->id);
      cursor = cursor->next;
    }
    mb_clear_runtime_state_locked(state);
  }
  LeaveCriticalSection(&state->lock);
  return 0;
}
#endif

MOONBIT_FFI_EXPORT int32_t mb_global_hotkey_platform_supported(void) {
#ifdef _WIN32
  mb_set_error_message("");
  return 1;
#elif defined(__linux__)
  Display *display;
  if (!mb_linux_load_x11()) {
    mb_set_error_message(
        "libX11 could not be loaded; install the X11 runtime and headers");
    return 0;
  }
  display = mb_x11_api.XOpenDisplay(NULL);
  if (display == NULL) {
    mb_set_error_message(
        "an X11 display is required; ensure DISPLAY is set or use XWayland");
    return 0;
  }
  mb_x11_api.XCloseDisplay(display);
  mb_set_error_message("");
  return 1;
#elif defined(__APPLE__)
  if (!mb_macos_load_api()) {
    mb_set_error_message("failed to load the macOS event frameworks");
    return 0;
  }
  mb_set_error_message("");
  return 1;
#else
  mb_set_error_message("this target does not provide a native global hotkey backend");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT mb_global_hotkey_state_t *mb_global_hotkey_create(void) {
  mb_global_hotkey_state_t *state;

  state = (mb_global_hotkey_state_t *)calloc(1, sizeof(*state));
  if (state == NULL) {
    mb_set_error_message("failed to allocate the native global hotkey state");
    return NULL;
  }

#ifdef _WIN32
  state->ready_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (state->ready_event == NULL) {
    free(state);
    mb_set_error_message("failed to create the Windows readiness event");
    return NULL;
  }
  InitializeCriticalSection(&state->lock);
  state->thread = CreateThread(NULL, 0, mb_windows_thread_main, state, 0,
                               &state->thread_id);
  if (state->thread == NULL) {
    DeleteCriticalSection(&state->lock);
    CloseHandle(state->ready_event);
    free(state);
    mb_set_error_message("failed to create the Windows hotkey thread");
    return NULL;
  }
  WaitForSingleObject(state->ready_event, INFINITE);
  mb_set_error_message("");
  return state;
#elif defined(__linux__)
  if (!mb_linux_load_x11()) {
    free(state);
    mb_set_error_message(
        "libX11 could not be loaded; install the X11 runtime and headers");
    return NULL;
  }
  state->display = mb_x11_api.XOpenDisplay(NULL);
  if (state->display == NULL) {
    free(state);
    mb_set_error_message(
        "an X11 display is required; ensure DISPLAY is set or use XWayland");
    return NULL;
  }
  state->root_window = DefaultRootWindow(state->display);
  state->lock_mask = LockMask;
  state->numlock_mask = mb_linux_detect_numlock_mask(state->display);
  if (!mb_init_sync_primitives(&state->lock, &state->ready_cond)) {
    mb_x11_api.XCloseDisplay(state->display);
    free(state);
    mb_set_error_message("failed to initialize Linux synchronization primitives");
    return NULL;
  }
  if (pipe(state->wake_pipe) != 0) {
    mb_destroy_sync_primitives(&state->lock, &state->ready_cond);
    mb_x11_api.XCloseDisplay(state->display);
    free(state);
    mb_set_error_message("failed to create the Linux wake pipe");
    return NULL;
  }
  if (pthread_create(&state->thread, NULL, mb_linux_thread_main, state) != 0) {
    close(state->wake_pipe[0]);
    close(state->wake_pipe[1]);
    mb_destroy_sync_primitives(&state->lock, &state->ready_cond);
    mb_x11_api.XCloseDisplay(state->display);
    free(state);
    mb_set_error_message("failed to create the Linux hotkey thread");
    return NULL;
  }
  state->thread_started = 1;
  pthread_mutex_lock(&state->lock);
  while (!state->ready) {
    pthread_cond_wait(&state->ready_cond, &state->lock);
  }
  pthread_mutex_unlock(&state->lock);
  mb_set_error_message("");
  return state;
#elif defined(__APPLE__)
  if (!mb_macos_load_api()) {
    free(state);
    mb_set_error_message("failed to load the macOS event frameworks");
    return NULL;
  }
  if (!mb_init_sync_primitives(&state->lock, &state->ready_cond)) {
    free(state);
    mb_set_error_message("failed to initialize macOS synchronization primitives");
    return NULL;
  }
  if (pthread_create(&state->thread, NULL, mb_macos_thread_main, state) != 0) {
    mb_destroy_sync_primitives(&state->lock, &state->ready_cond);
    free(state);
    mb_set_error_message("failed to create the macOS hotkey thread");
    return NULL;
  }
  state->thread_started = 1;
  pthread_mutex_lock(&state->lock);
  while (!state->ready) {
    pthread_cond_wait(&state->ready_cond, &state->lock);
  }
  pthread_mutex_unlock(&state->lock);
  if (!state->running) {
    pthread_join(state->thread, NULL);
    mb_destroy_sync_primitives(&state->lock, &state->ready_cond);
    mb_set_error_message(state->startup_error);
    free(state);
    return NULL;
  }
  mb_set_error_message("");
  return state;
#else
  free(state);
  mb_set_error_message("this target does not provide a native global hotkey backend");
  return NULL;
#endif
}

MOONBIT_FFI_EXPORT void mb_global_hotkey_destroy(
    mb_global_hotkey_state_t *state) {
  if (state == NULL) {
    return;
  }

#ifdef _WIN32
  PostThreadMessage(state->thread_id, MB_WIN_MSG_QUIT, 0, 0);
  WaitForSingleObject(state->thread, INFINITE);
  DeleteCriticalSection(&state->lock);
  CloseHandle(state->thread);
  CloseHandle(state->ready_event);
  free(state);
#elif defined(__linux__)
  if (state->thread_started) {
    pthread_mutex_lock(&state->lock);
    state->running = 0;
    pthread_mutex_unlock(&state->lock);
    (void)write(state->wake_pipe[1], "q", 1);
    pthread_join(state->thread, NULL);
  }
  pthread_mutex_lock(&state->lock);
  {
    mb_registration_t *cursor = state->registrations;
    while (cursor != NULL) {
      unsigned int base_modifiers = cursor->modifiers;
      unsigned int variants[4] = {
          base_modifiers,
          base_modifiers | state->lock_mask,
          base_modifiers | state->numlock_mask,
          base_modifiers | state->lock_mask | state->numlock_mask,
      };
      size_t index;
      for (index = 0; index < 4; index++) {
        mb_x11_api.XUngrabKey(state->display, (int)cursor->keycode, variants[index],
                              state->root_window);
      }
      cursor = cursor->next;
    }
    mb_x11_api.XFlush(state->display);
    mb_clear_runtime_state_locked(state);
  }
  pthread_mutex_unlock(&state->lock);
  close(state->wake_pipe[0]);
  close(state->wake_pipe[1]);
  mb_x11_api.XCloseDisplay(state->display);
  mb_destroy_sync_primitives(&state->lock, &state->ready_cond);
  free(state);
#elif defined(__APPLE__)
  if (state->thread_started) {
    CFRunLoopRef run_loop = NULL;
    pthread_mutex_lock(&state->lock);
    if (state->run_loop != NULL) {
      run_loop = (CFRunLoopRef)mb_macos_api.CFRetain(state->run_loop);
    }
    pthread_mutex_unlock(&state->lock);
    if (run_loop != NULL) {
      mb_macos_api.CFRunLoopStop(run_loop);
      mb_macos_api.CFRunLoopWakeUp(run_loop);
      mb_macos_api.CFRelease(run_loop);
    }
    pthread_join(state->thread, NULL);
  }
  pthread_mutex_lock(&state->lock);
  mb_clear_runtime_state_locked(state);
  pthread_mutex_unlock(&state->lock);
  mb_destroy_sync_primitives(&state->lock, &state->ready_cond);
  free(state);
#else
  free(state);
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_global_hotkey_register(
    mb_global_hotkey_state_t *state,
    int32_t id,
    int32_t modifiers,
    moonbit_bytes_t key_name) {
  char *name;

  if (state == NULL) {
    mb_set_error_message("the native global hotkey state is null");
    return 1;
  }
  name = mb_copy_bytes_to_c_string(key_name);
  if (name == NULL) {
    mb_set_error_message("failed to copy the key name for registration");
    return 1;
  }

#ifdef _WIN32
  {
    mb_win_command_t command;
    UINT keycode = 0;
    if (!mb_windows_keycode_from_name(name, &keycode)) {
      free(name);
      mb_set_error_message("unsupported Windows hotkey key");
      return 1;
    }
    memset(&command, 0, sizeof(command));
    command.done_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (command.done_event == NULL) {
      free(name);
      mb_set_error_message("failed to create the Windows registration event");
      return 1;
    }
    command.id = id;
    command.modifiers = mb_windows_modifiers((uint32_t)modifiers);
    command.keycode = keycode;
    if (!PostThreadMessage(state->thread_id, MB_WIN_MSG_REGISTER, 0,
                           (LPARAM)&command)) {
      CloseHandle(command.done_event);
      free(name);
      mb_set_error_message("failed to post the Windows registration command");
      return 1;
    }
    WaitForSingleObject(command.done_event, INFINITE);
    CloseHandle(command.done_event);
    free(name);
    if (command.status == 0) {
      mb_set_error_message("");
      return 0;
    }
    mb_set_error_message("the Windows hotkey is unavailable or already in use");
    return 1;
  }
#elif defined(__linux__)
  {
    KeyCode keycode = 0;
    unsigned int base_modifiers = mb_linux_modifiers((uint32_t)modifiers);
    unsigned int variants[4];
    size_t index;
    if (!mb_linux_keycode_from_name(state->display, name, &keycode)) {
      free(name);
      mb_set_error_message("unsupported X11 hotkey key");
      return 1;
    }
    variants[0] = base_modifiers;
    variants[1] = base_modifiers | state->lock_mask;
    variants[2] = base_modifiers | state->numlock_mask;
    variants[3] = base_modifiers | state->lock_mask | state->numlock_mask;

    mb_linux_x11_error_code = 0;
    mb_x11_api.XSetErrorHandler(mb_linux_x11_error_handler);
    for (index = 0; index < 4; index++) {
      mb_x11_api.XGrabKey(state->display, keycode, variants[index], state->root_window,
                          True, GrabModeAsync, GrabModeAsync);
    }
    mb_x11_api.XSync(state->display, False);
    mb_x11_api.XSetErrorHandler(NULL);
    if (mb_linux_x11_error_code != 0) {
      for (index = 0; index < 4; index++) {
        mb_x11_api.XUngrabKey(state->display, keycode, variants[index],
                              state->root_window);
      }
      mb_x11_api.XFlush(state->display);
      free(name);
      mb_set_error_message("the X11 hotkey is unavailable or already in use");
      return 1;
    }

    pthread_mutex_lock(&state->lock);
    mb_add_registration_locked(state, id, base_modifiers, keycode);
    pthread_mutex_unlock(&state->lock);
    mb_x11_api.XFlush(state->display);
    free(name);
    mb_set_error_message("");
    return 0;
  }
#elif defined(__APPLE__)
  {
    uint32_t keycode = 0;
    if (!mb_macos_keycode_from_name(name, &keycode)) {
      free(name);
      mb_set_error_message("unsupported macOS hotkey key");
      return 1;
    }
    pthread_mutex_lock(&state->lock);
    mb_add_registration_locked(state, id, (uint32_t)modifiers, keycode);
    pthread_mutex_unlock(&state->lock);
    free(name);
    mb_set_error_message("");
    return 0;
  }
#else
  free(name);
  mb_set_error_message("this target does not provide a native global hotkey backend");
  return 1;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_global_hotkey_unregister(
    mb_global_hotkey_state_t *state,
    int32_t id) {
  if (state == NULL) {
    mb_set_error_message("the native global hotkey state is null");
    return 1;
  }

#ifdef _WIN32
  {
    mb_win_command_t command;
    memset(&command, 0, sizeof(command));
    command.done_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (command.done_event == NULL) {
      mb_set_error_message("failed to create the Windows unregistration event");
      return 1;
    }
    command.id = id;
    if (!PostThreadMessage(state->thread_id, MB_WIN_MSG_UNREGISTER, 0,
                           (LPARAM)&command)) {
      CloseHandle(command.done_event);
      mb_set_error_message("failed to post the Windows unregistration command");
      return 1;
    }
    WaitForSingleObject(command.done_event, INFINITE);
    CloseHandle(command.done_event);
    if (command.status == 0) {
      mb_set_error_message("");
      return 0;
    }
    mb_set_error_message("the Windows hotkey could not be unregistered");
    return 1;
  }
#elif defined(__linux__)
  {
    unsigned int base_modifiers = 0;
    unsigned int keycode = 0;
    unsigned int variants[4];
    size_t index;

    pthread_mutex_lock(&state->lock);
    {
      mb_registration_t *registration = mb_find_registration_locked(state, id);
      if (registration == NULL) {
        pthread_mutex_unlock(&state->lock);
        mb_set_error_message("the X11 hotkey id was not found");
        return 1;
      }
      base_modifiers = registration->modifiers;
      keycode = registration->keycode;
    }
    pthread_mutex_unlock(&state->lock);

    variants[0] = base_modifiers;
    variants[1] = base_modifiers | state->lock_mask;
    variants[2] = base_modifiers | state->numlock_mask;
    variants[3] = base_modifiers | state->lock_mask | state->numlock_mask;

    mb_linux_x11_error_code = 0;
    mb_x11_api.XSetErrorHandler(mb_linux_x11_error_handler);
    for (index = 0; index < 4; index++) {
      mb_x11_api.XUngrabKey(state->display, (int)keycode, variants[index],
                            state->root_window);
    }
    mb_x11_api.XSync(state->display, False);
    mb_x11_api.XSetErrorHandler(NULL);
    if (mb_linux_x11_error_code != 0) {
      mb_set_error_message("the X11 hotkey could not be unregistered");
      return 1;
    }

    pthread_mutex_lock(&state->lock);
    mb_remove_registration_locked(state, id, NULL, NULL);
    pthread_mutex_unlock(&state->lock);
    mb_x11_api.XFlush(state->display);
    mb_set_error_message("");
    return 0;
  }
#elif defined(__APPLE__)
  pthread_mutex_lock(&state->lock);
  if (!mb_remove_registration_locked(state, id, NULL, NULL)) {
    pthread_mutex_unlock(&state->lock);
    mb_set_error_message("the macOS hotkey id was not found");
    return 1;
  }
  pthread_mutex_unlock(&state->lock);
  mb_set_error_message("");
  return 0;
#else
  mb_set_error_message("this target does not provide a native global hotkey backend");
  return 1;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_global_hotkey_take_triggered_id(
    mb_global_hotkey_state_t *state) {
  if (state == NULL) {
    return 0;
  }

#ifdef _WIN32
  EnterCriticalSection(&state->lock);
  {
    int32_t id = mb_take_triggered_id_locked(state);
    LeaveCriticalSection(&state->lock);
    return id;
  }
#elif defined(__linux__) || defined(__APPLE__)
  pthread_mutex_lock(&state->lock);
  {
    int32_t id = mb_take_triggered_id_locked(state);
    pthread_mutex_unlock(&state->lock);
    return id;
  }
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_global_hotkey_last_error_message(void) {
  return mb_make_bytes_from_buffer(mb_last_error_message,
                                   strlen(mb_last_error_message));
}
