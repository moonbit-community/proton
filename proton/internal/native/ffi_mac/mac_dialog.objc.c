#if defined(__APPLE__)

#include "mac_dialog.h"

#include "mac_window.h"
#include "../ffi/src/proton_engine.h"
#include "../ffi/src/proton_event.h"

#import <Cocoa/Cocoa.h>

#include <dispatch/dispatch.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct proton_engine_dialog_request {
  int64_t id;
  int owner_kind;
  uintptr_t owner_id;
  int64_t event_window;
  int refs;
  int completed;
  void *platform_state;
  struct proton_engine_dialog_request *next;
} proton_engine_dialog_request_t;

static int64_t g_next_dialog_id = 1;
static proton_engine_dialog_request_t *g_dialog_requests = NULL;
static pthread_mutex_t g_dialog_lock = PTHREAD_MUTEX_INITIALIZER;

static void proton_engine_set_message(char *error,
                                      size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static NSString *proton_engine_string_from_utf8(
    const char *value,
    int32_t value_len) {
  if (value == NULL || value_len <= 0) {
    return @"";
  }
  NSString *text = [[NSString alloc]
      initWithBytes:value
             length:(NSUInteger)value_len
           encoding:NSUTF8StringEncoding];
  return text != nil ? [text autorelease] : @"";
}

static NSString *proton_engine_dialog_label(const char *label) {
  return proton_engine_string_from_utf8(label, (int32_t)strlen(label));
}

static void proton_engine_dialog_lock(void) {
  pthread_mutex_lock(&g_dialog_lock);
}

static void proton_engine_dialog_unlock(void) {
  pthread_mutex_unlock(&g_dialog_lock);
}

static proton_engine_dialog_request_t *
proton_engine_dialog_request_remove_locked(int owner_kind,
                                           uintptr_t owner_id,
                                           int64_t id) {
  proton_engine_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    proton_engine_dialog_request_t *request = *cursor;
    if (request->id == id && request->owner_kind == owner_kind &&
        request->owner_id == owner_id) {
      *cursor = request->next;
      request->next = NULL;
      return request;
    }
    cursor = &request->next;
  }
  return NULL;
}

static void proton_engine_dialog_request_free(
    proton_engine_dialog_request_t *request) {
  if (request == NULL) {
    return;
  }
  free(request);
}

static void proton_engine_dialog_request_retain(
    proton_engine_dialog_request_t *request) {
  if (request == NULL) {
    return;
  }
  proton_engine_dialog_lock();
  request->refs++;
  proton_engine_dialog_unlock();
}

static void proton_engine_dialog_request_release(
    proton_engine_dialog_request_t *request) {
  if (request == NULL) {
    return;
  }
  int should_free = 0;
  proton_engine_dialog_lock();
  request->refs--;
  should_free = request->refs == 0;
  proton_engine_dialog_unlock();
  if (should_free) {
    proton_engine_dialog_request_free(request);
  }
}

enum {
  PROTON_ENGINE_DIALOG_OWNER_WINDOW = 1,
  PROTON_ENGINE_DIALOG_OWNER_RUNTIME = 2,
};

static int32_t proton_engine_dialog_request_create_for_owner(
    int owner_kind,
    uintptr_t owner_id,
    int64_t event_window,
    proton_engine_dialog_request_t **out_request,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  if (out_request == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len, "out_dialog is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_request = NULL;
  *out_dialog = PROTON_INVALID_HANDLE;
  if (owner_id == 0) {
    proton_engine_set_message(error, error_len, "dialog owner is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }

  proton_engine_dialog_request_t *request =
      (proton_engine_dialog_request_t *)calloc(1, sizeof(*request));
  if (request == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog request");
    return PROTON_ERR_ENGINE;
  }

  proton_engine_dialog_lock();
  request->id = g_next_dialog_id++;
  if (g_next_dialog_id == 0) {
    g_next_dialog_id = 1;
  }
  request->refs = 1;
  request->owner_kind = owner_kind;
  request->owner_id = owner_id;
  request->event_window = event_window;
  request->next = g_dialog_requests;
  g_dialog_requests = request;
  proton_engine_dialog_unlock();

  *out_request = request;
  *out_dialog = request->id;
  return PROTON_OK;
}

static int32_t proton_engine_dialog_request_create(
    proton_engine_window_t *window,
    proton_engine_dialog_request_t **out_request,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  if (proton_engine_window_is_headless(window)) {
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window == NULL || proton_engine_window_get_native_window(window) == nil) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_dialog_request_create_for_owner(
      PROTON_ENGINE_DIALOG_OWNER_WINDOW,
      (uintptr_t)proton_engine_window_native_id(window),
      proton_engine_window_public_id(window), out_request, out_dialog, error,
      error_len);
}

static void proton_engine_dialog_complete(
    proton_engine_dialog_request_t *request,
    int32_t status,
    const char *result,
    const char *error_message) {
  if (request == NULL) {
    return;
  }
  proton_engine_dialog_lock();
  if (request->completed) {
    proton_engine_dialog_unlock();
    return;
  }
  request->completed = 1;
  proton_engine_dialog_request_t *removed =
      proton_engine_dialog_request_remove_locked(
          request->owner_kind, request->owner_id, request->id);
  proton_engine_dialog_unlock();

  proton_event_t *event = proton_event_create(PROTON_EVENT_DIALOG_COMPLETED);
  if (event != NULL) {
    event->window = request->event_window;
    event->request_id = request->id;
    event->int_a = status;
    if (!proton_event_set_text(&event->text_a,
                               status == PROTON_OK && result != NULL
                                   ? result
                                   : "") ||
        !proton_event_set_text(&event->text_b,
                               error_message != NULL ? error_message : "")) {
      proton_event_destroy(event);
    } else {
      (void)proton_event_publish(event);
    }
  }
  proton_engine_dialog_request_release(removed);
}

static NSAlertStyle proton_engine_alert_style(int32_t level);

@interface ProtonRuntimeAlertController : NSObject {
 @private
  proton_engine_dialog_request_t *request_;
  NSAlert *alert_;
  NSModalSession session_;
  BOOL dismissed_;
  BOOL finished_;
}
- (instancetype)initWithRequest:(proton_engine_dialog_request_t *)request
                           title:(NSString *)title
                         message:(NSString *)message
                           level:(int32_t)level
                         okLabel:(NSString *)ok_label;
- (void)show;
- (void)tick;
- (void)finish;
- (void)cancel;
- (void)dismiss:(id)sender;
@end

@implementation ProtonRuntimeAlertController
- (instancetype)initWithRequest:(proton_engine_dialog_request_t *)request
                           title:(NSString *)title
                         message:(NSString *)message
                           level:(int32_t)level
                         okLabel:(NSString *)ok_label {
  self = [super init];
  if (self != nil) {
    request_ = request;
    alert_ = [[NSAlert alloc] init];
    [alert_ setMessageText:title];
    [alert_ setInformativeText:message];
    [alert_ setAlertStyle:proton_engine_alert_style(level)];
    NSButton *button = [alert_ addButtonWithTitle:ok_label];
    [button setTarget:self];
    [button setAction:@selector(dismiss:)];
    session_ = nil;
    dismissed_ = NO;
    finished_ = NO;
    [self retain];
  }
  return self;
}

- (void)show {
  if (@available(macOS 14.0, *)) {
    [NSApp activate];
  } else {
    [NSApp activateIgnoringOtherApps:YES];
  }
  session_ = [NSApp beginModalSessionForWindow:[alert_ window]];
  [self tick];
}

- (void)tick {
  if (session_ == nil || finished_) {
    return;
  }
  if (dismissed_) {
    [self finish];
    return;
  }
  NSModalResponse response = [NSApp runModalSession:session_];
  if (response == NSModalResponseContinue) {
    return;
  }
  [self finish];
}

- (void)finish {
  if (session_ == nil || finished_) {
    return;
  }
  finished_ = YES;
  [NSApp endModalSession:session_];
  session_ = nil;
  request_->platform_state = NULL;
  proton_engine_dialog_complete(request_, PROTON_OK, "", NULL);
  [[alert_ window] orderOut:nil];
  [alert_ release];
  alert_ = nil;
  proton_engine_dialog_request_release(request_);
  request_ = NULL;
  [self release];
}

- (void)dismiss:(id)sender {
  (void)sender;
  dismissed_ = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self tick];
  });
}

- (void)cancel {
  if (finished_) {
    return;
  }
  finished_ = YES;
  if (session_ != nil) {
    [NSApp endModalSession:session_];
    session_ = nil;
  }
  request_->platform_state = NULL;
  [[alert_ window] orderOut:nil];
  [alert_ release];
  alert_ = nil;
  proton_engine_dialog_request_release(request_);
  request_ = NULL;
  [self release];
}
@end

static char *proton_engine_dialog_result_from_string(NSString *value) {
  NSData *data = [(value != nil ? value : @"")
      dataUsingEncoding:NSUTF8StringEncoding
   allowLossyConversion:NO];
  if (data == nil || [data length] > (NSUInteger)(INT32_MAX - 1)) {
    return NULL;
  }
  char *copy = (char *)malloc([data length] + 1);
  if (copy == NULL) {
    return NULL;
  }
  if ([data length] > 0) {
    memcpy(copy, [data bytes], [data length]);
  }
  copy[[data length]] = '\0';
  return copy;
}

static void proton_engine_dialog_complete_string(
    proton_engine_dialog_request_t *request,
    NSString *value) {
  char *result = proton_engine_dialog_result_from_string(value);
  if (result == NULL) {
    proton_engine_dialog_complete(request, PROTON_ERR_ENGINE, NULL,
                                  "failed to encode dialog result");
    return;
  }
  proton_engine_dialog_complete(request, PROTON_OK, result, NULL);
  free(result);
}

void proton_engine_dialog_complete_window_closed(uint64_t native_id) {
  while (1) {
    proton_engine_dialog_request_t *matched = NULL;
    proton_engine_dialog_lock();
    for (proton_engine_dialog_request_t *request = g_dialog_requests;
         request != NULL; request = request->next) {
      if (request->owner_kind == PROTON_ENGINE_DIALOG_OWNER_WINDOW &&
          request->owner_id == (uintptr_t)native_id && !request->completed) {
        request->refs++;
        matched = request;
        break;
      }
    }
    proton_engine_dialog_unlock();
    if (matched == NULL) {
      return;
    }
    proton_engine_dialog_complete(matched, PROTON_ERR_DESTROYED, NULL,
                                  "window closed before dialog completed");
    proton_engine_dialog_request_release(matched);
  }
}

void proton_engine_dialog_dispose_runtime(void *runtime) {
  proton_engine_dialog_request_t *removed = NULL;
  proton_engine_dialog_lock();
  proton_engine_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    proton_engine_dialog_request_t *request = *cursor;
    if (request->owner_kind == PROTON_ENGINE_DIALOG_OWNER_RUNTIME &&
        request->owner_id == (uintptr_t)runtime) {
      *cursor = request->next;
      request->next = removed;
      removed = request;
      continue;
    }
    cursor = &request->next;
  }
  proton_engine_dialog_unlock();

  while (removed != NULL) {
    proton_engine_dialog_request_t *request = removed;
    removed = request->next;
    request->next = NULL;
    ProtonRuntimeAlertController *controller =
        request->platform_state != NULL
            ? (ProtonRuntimeAlertController *)request->platform_state
            : nil;
    [controller retain];
    [controller cancel];
    [controller release];
    proton_engine_dialog_request_release(request);
  }
}

static int32_t proton_engine_dialog_begin_on_parent(
    proton_engine_window_t *window,
    proton_engine_dialog_request_t *request,
    void (^start_dialog)(NSWindow *parent),
    void (^cleanup_without_start)(void)) {
  if (window == NULL || request == NULL || start_dialog == nil) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  uint64_t native_id = proton_engine_window_native_id(window);
  NSWindow *parent = proton_engine_window_retain_native_window(window);
  proton_engine_dialog_request_retain(request);
  dispatch_async(dispatch_get_main_queue(), ^{
    @autoreleasepool {
      proton_engine_dialog_lock();
      int cancelled = request->completed;
      proton_engine_dialog_unlock();
      if (cancelled) {
        if (cleanup_without_start != nil) {
          cleanup_without_start();
        }
        [parent release];
        proton_engine_dialog_request_release(request);
        return;
      }
      proton_engine_window_t *current =
          proton_engine_window_lookup_native_id(native_id);
      if (proton_engine_window_is_closed_or_missing(current)) {
        if (cleanup_without_start != nil) {
          cleanup_without_start();
        }
        [parent release];
        proton_engine_dialog_complete(request, PROTON_ERR_DESTROYED, NULL,
                                      "window closed before dialog started");
        proton_engine_dialog_request_release(request);
        return;
      }
      [NSApp activateIgnoringOtherApps:YES];
      start_dialog(parent);
    }
  });
  return PROTON_OK;
}

static NSAlertStyle proton_engine_alert_style(int32_t level) {
  switch (level) {
  case 1:
    return NSAlertStyleWarning;
  case 2:
    return NSAlertStyleCritical;
  default:
    return NSAlertStyleInformational;
  }
}

int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {

  if (proton_engine_runtime_is_headless(runtime)) {
    if (out_dialog != NULL) {
      *out_dialog = PROTON_INVALID_HANDLE;
    }
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (proton_engine_runtime_dialog_ok_label(runtime)[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog label is not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_dialog_request_t *request = NULL;
  int32_t status = proton_engine_dialog_request_create_for_owner(
      PROTON_ENGINE_DIALOG_OWNER_RUNTIME, (uintptr_t)runtime,
      PROTON_INVALID_HANDLE, &request, out_dialog, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  NSString *title = proton_engine_string_from_utf8(title_utf8, title_len);
  NSString *message = proton_engine_string_from_utf8(message_utf8, message_len);
  NSString *ok_label = proton_engine_dialog_label(
      proton_engine_runtime_dialog_ok_label(runtime));
  proton_engine_dialog_request_retain(request);
  ProtonRuntimeAlertController *controller =
      [[ProtonRuntimeAlertController alloc] initWithRequest:request
                                                     title:title
                                                   message:message
                                                     level:level
                                                   okLabel:ok_label];
  if (controller == nil) {
    proton_engine_dialog_complete(request, PROTON_ERR_PLATFORM, NULL,
                                  "failed to create runtime alert");
    proton_engine_dialog_request_release(request);
  } else {
    request->platform_state = controller;
    [controller show];
    [controller release];
  }
  return PROTON_OK;
}

static void proton_engine_configure_file_panel(NSSavePanel *panel,
                                               NSString *initial_path,
                                               BOOL save_mode) {
  if (initial_path == nil || [initial_path length] == 0) {
    return;
  }
  BOOL is_dir = NO;
  NSFileManager *file_manager = [NSFileManager defaultManager];
  if ([file_manager fileExistsAtPath:initial_path isDirectory:&is_dir] &&
      is_dir) {
    [panel setDirectoryURL:[NSURL fileURLWithPath:initial_path]];
    return;
  }
  NSString *directory = [initial_path stringByDeletingLastPathComponent];
  NSString *name = [initial_path lastPathComponent];
  if ([directory length] > 0) {
    [panel setDirectoryURL:[NSURL fileURLWithPath:directory]];
  }
  if (save_mode && [name length] > 0) {
    [panel setNameFieldStringValue:name];
  }
}

enum {
  PROTON_ENGINE_FILE_DIALOG_OPEN = 0,
  PROTON_ENGINE_FILE_DIALOG_SAVE = 1,
  PROTON_ENGINE_FILE_DIALOG_CHOOSE_DIRECTORY = 2,
};

static NSSavePanel *proton_engine_make_file_panel(int32_t mode,
                                                  NSString *title,
                                                  NSString *path) {
  BOOL save_mode = mode == PROTON_ENGINE_FILE_DIALOG_SAVE;
  NSSavePanel *panel = save_mode ? [NSSavePanel savePanel]
                                 : [NSOpenPanel openPanel];
  if ([title length] > 0) {
    [panel setTitle:title];
  }
  if (!save_mode) {
    NSOpenPanel *open_panel = (NSOpenPanel *)panel;
    BOOL choose_directories =
        mode == PROTON_ENGINE_FILE_DIALOG_CHOOSE_DIRECTORY;
    [open_panel setCanChooseFiles:!choose_directories];
    [open_panel setCanChooseDirectories:choose_directories];
    [open_panel setAllowsMultipleSelection:NO];
  }
  proton_engine_configure_file_panel(panel, path, save_mode);
  return panel;
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

  proton_engine_runtime_t *runtime = proton_engine_window_get_runtime(window);
  if (proton_engine_runtime_dialog_ok_label(runtime)[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog label is not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_dialog_request_t *request = NULL;
  int32_t status = proton_engine_dialog_request_create(
      window, &request, out_dialog, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  NSString *title = [proton_engine_string_from_utf8(title_utf8, title_len) retain];
  NSString *message =
      [proton_engine_string_from_utf8(message_utf8, message_len) retain];
  status = proton_engine_dialog_begin_on_parent(
      window, request, ^(NSWindow *parent) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:title];
        [alert setInformativeText:message];
        [alert setAlertStyle:proton_engine_alert_style(level)];
        [alert addButtonWithTitle:proton_engine_dialog_label(
                                      proton_engine_runtime_dialog_ok_label(
                                          runtime))];
        request->platform_state = [[alert window] retain];
        [alert beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse returnCode) {
                        (void)returnCode;
                        NSWindow *sheet = (NSWindow *)request->platform_state;
                        request->platform_state = NULL;
                        [sheet release];
                        proton_engine_dialog_complete(request, PROTON_OK, "",
                                                      NULL);
                        [title release];
                        [message release];
                        [parent release];
                        proton_engine_dialog_request_release(request);
                      }];
      }, ^{
        [title release];
        [message release];
      });
  if (status != PROTON_OK) {
    [title release];
    [message release];
    proton_engine_dialog_request_release(request);
  }
  return status;
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

  proton_engine_runtime_t *runtime = proton_engine_window_get_runtime(window);
  if (proton_engine_runtime_dialog_ok_label(runtime)[0] == '\0' ||
      proton_engine_runtime_dialog_cancel_label(runtime)[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog labels are not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_dialog_request_t *request = NULL;
  int32_t status = proton_engine_dialog_request_create(
      window, &request, out_dialog, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  NSString *title = [proton_engine_string_from_utf8(title_utf8, title_len) retain];
  NSString *message =
      [proton_engine_string_from_utf8(message_utf8, message_len) retain];
  status = proton_engine_dialog_begin_on_parent(
      window, request, ^(NSWindow *parent) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:title];
        [alert setInformativeText:message];
        [alert setAlertStyle:proton_engine_alert_style(level)];
        [alert addButtonWithTitle:proton_engine_dialog_label(
                                      proton_engine_runtime_dialog_ok_label(
                                          runtime))];
        [alert addButtonWithTitle:proton_engine_dialog_label(
                                      proton_engine_runtime_dialog_cancel_label(
                                          runtime))];
        request->platform_state = [[alert window] retain];
        [alert beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse returnCode) {
                        const char *result =
                            returnCode == NSAlertFirstButtonReturn ? "1" : "0";
                        NSWindow *sheet = (NSWindow *)request->platform_state;
                        request->platform_state = NULL;
                        [sheet release];
                        proton_engine_dialog_complete(request, PROTON_OK,
                                                      result, NULL);
                        [title release];
                        [message release];
                        [parent release];
                        proton_engine_dialog_request_release(request);
                      }];
      }, ^{
        [title release];
        [message release];
      });
  if (status != PROTON_OK) {
    [title release];
    [message release];
    proton_engine_dialog_request_release(request);
  }
  return status;
}

static int32_t proton_engine_window_begin_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int32_t mode,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  proton_engine_dialog_request_t *request = NULL;
  int32_t status = proton_engine_dialog_request_create(
      window, &request, out_dialog, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  NSString *title = [proton_engine_string_from_utf8(title_utf8, title_len) retain];
  NSString *path = [proton_engine_string_from_utf8(path_utf8, path_len) retain];
  status = proton_engine_dialog_begin_on_parent(
      window, request, ^(NSWindow *parent) {
        NSSavePanel *panel = proton_engine_make_file_panel(mode, title, path);
        request->platform_state = [panel retain];
        [panel beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse returnCode) {
                        NSString *result = @"";
                        if (returnCode == NSModalResponseOK &&
                            [panel URL] != nil) {
                          result = [[panel URL] path] ?: @"";
                        }
                        request->platform_state = NULL;
                        [panel release];
                        proton_engine_dialog_complete_string(request, result);
                        [title release];
                        [path release];
                        [parent release];
                        proton_engine_dialog_request_release(request);
                      }];
      }, ^{
        [title release];
        [path release];
      });
  if (status != PROTON_OK) {
    [title release];
    [path release];
    proton_engine_dialog_request_release(request);
  }
  return status;
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
      PROTON_ENGINE_FILE_DIALOG_OPEN, out_dialog, error, error_len);
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
      PROTON_ENGINE_FILE_DIALOG_SAVE, out_dialog, error, error_len);
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
      PROTON_ENGINE_FILE_DIALOG_CHOOSE_DIRECTORY, out_dialog, error,
      error_len);
}

int32_t proton_engine_window_cancel_dialog(proton_engine_window_t *window,
                                           int64_t dialog,
                                           char *error,
                                           size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  uintptr_t owner_id =
      (uintptr_t)proton_engine_window_native_id(window);
  proton_engine_dialog_lock();
  proton_engine_dialog_request_t *request =
      proton_engine_dialog_request_remove_locked(
          PROTON_ENGINE_DIALOG_OWNER_WINDOW, owner_id, dialog);
  if (request == NULL) {
    proton_engine_dialog_unlock();
    return PROTON_OK;
  }
  request->completed = 1;
  NSWindow *sheet = request->platform_state != NULL
                        ? [(NSWindow *)request->platform_state retain]
                        : nil;
  proton_engine_dialog_unlock();
  if (sheet != nil) {
    NSWindow *parent = [sheet sheetParent];
    if (parent != nil) {
      [parent endSheet:sheet returnCode:NSModalResponseCancel];
    } else {
      [sheet orderOut:nil];
    }
    [sheet release];
  }
  proton_engine_dialog_request_release(request);
  return PROTON_OK;
}

#endif
