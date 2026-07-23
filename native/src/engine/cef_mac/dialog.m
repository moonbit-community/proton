#include "dialog.h"

#include "../../app_runner.h"
#include "window.h"
#include "../../proton_engine.h"

#import <Cocoa/Cocoa.h>

#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_DIALOG_RETURN_ON_MAIN(call)                                 \
  do {                                                                    \
    if (!pthread_main_np()) {                                             \
      return proton_app_dispatch_sync_int(^{ return (call); });           \
    }                                                                     \
  } while (0)

typedef struct proton_engine_dialog_request {
  int64_t id;
  int owner_kind;
  uintptr_t owner_id;
  int refs;
  int completed;
  int32_t status;
  char *result;
  char error[512];
  void *platform_state;
  struct proton_engine_dialog_request *next;
} proton_engine_dialog_request_t;

static int64_t g_next_dialog_id = 1;
static proton_engine_dialog_request_t *g_dialog_requests = NULL;
static pthread_mutex_t g_dialog_lock = PTHREAD_MUTEX_INITIALIZER;
static proton_engine_dialog_signal_callback_t g_dialog_signal_callback = NULL;

static void proton_engine_set_message(char *error,
                                      size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static char *proton_engine_strdup(const char *value) {
  if (value == NULL) {
    value = "";
  }
  size_t len = strlen(value);
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, value, len + 1);
  return copy;
}

void proton_engine_dialog_set_signal_callback(
    proton_engine_dialog_signal_callback_t callback) {
  g_dialog_signal_callback = callback;
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

static void proton_engine_dialog_lock(void) {
  pthread_mutex_lock(&g_dialog_lock);
}

static void proton_engine_dialog_unlock(void) {
  pthread_mutex_unlock(&g_dialog_lock);
}

static proton_engine_dialog_request_t *proton_engine_dialog_request_find_locked(
    int owner_kind,
    uintptr_t owner_id,
    int64_t id) {
  for (proton_engine_dialog_request_t *request = g_dialog_requests;
       request != NULL; request = request->next) {
    if (request->id == id && request->owner_kind == owner_kind &&
        request->owner_id == owner_id) {
      return request;
    }
  }
  return NULL;
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
  free(request->result);
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
  if (window == NULL || proton_engine_window_get_native_window(window) == nil) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_dialog_request_create_for_owner(
      PROTON_ENGINE_DIALOG_OWNER_WINDOW,
      (uintptr_t)proton_engine_window_native_id(window), out_request,
      out_dialog, error, error_len);
}

static void proton_engine_dialog_complete(
    proton_engine_dialog_request_t *request,
    int32_t status,
    const char *result,
    const char *error_message) {
  if (request == NULL) {
    return;
  }
  char *result_copy = NULL;
  if (status == PROTON_OK) {
    result_copy = proton_engine_strdup(result != NULL ? result : "");
    if (result_copy == NULL) {
      status = PROTON_ERR_ENGINE;
      error_message = "failed to copy dialog result";
    }
  }

  proton_engine_dialog_lock();
  if (!request->completed) {
    request->completed = 1;
    request->status = status;
    request->result = result_copy;
    result_copy = NULL;
    snprintf(request->error, sizeof(request->error), "%s",
             error_message != NULL ? error_message : "");
  }
  proton_engine_dialog_unlock();
  free(result_copy);
  if (g_dialog_signal_callback != NULL) {
    g_dialog_signal_callback(PROTON_WAIT_PLATFORM);
  }
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
                           level:(int32_t)level;
- (void)show;
- (void)tick;
- (void)cancel;
- (void)dismiss:(id)sender;
@end

@implementation ProtonRuntimeAlertController
- (instancetype)initWithRequest:(proton_engine_dialog_request_t *)request
                           title:(NSString *)title
                         message:(NSString *)message
                           level:(int32_t)level {
  self = [super init];
  if (self != nil) {
    request_ = request;
    alert_ = [[NSAlert alloc] init];
    [alert_ setMessageText:title];
    [alert_ setInformativeText:message];
    [alert_ setAlertStyle:proton_engine_alert_style(level)];
    NSButton *button = [alert_ addButtonWithTitle:@"OK"];
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
  NSModalResponse response = [NSApp runModalSession:session_];
  if (!dismissed_ && response == NSModalResponseContinue) {
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
  [NSApp stopModal];
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
  proton_engine_dialog_lock();
  for (proton_engine_dialog_request_t *request = g_dialog_requests;
       request != NULL; request = request->next) {
    if (request->owner_kind == PROTON_ENGINE_DIALOG_OWNER_WINDOW &&
        request->owner_id == (uintptr_t)native_id && !request->completed) {
      request->completed = 1;
      request->status = PROTON_ERR_DESTROYED;
      snprintf(request->error, sizeof(request->error), "%s",
               "window closed before dialog completed");
    }
  }
  proton_engine_dialog_unlock();
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
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_runtime_begin_message_dialog(
      runtime, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len));
  proton_engine_dialog_request_t *request = NULL;
  int32_t status = proton_engine_dialog_request_create_for_owner(
      PROTON_ENGINE_DIALOG_OWNER_RUNTIME, (uintptr_t)runtime, &request,
      out_dialog, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  NSString *title = proton_engine_string_from_utf8(title_utf8, title_len);
  NSString *message = proton_engine_string_from_utf8(message_utf8, message_len);
  proton_engine_dialog_request_retain(request);
  ProtonRuntimeAlertController *controller =
      [[ProtonRuntimeAlertController alloc] initWithRequest:request
                                                     title:title
                                                   message:message
                                                     level:level];
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

int32_t proton_engine_runtime_poll_dialog_result(
    proton_engine_runtime_t *runtime,
    int64_t dialog,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len) {
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_runtime_poll_dialog_result(
      runtime, dialog, buffer, buffer_len, out_required_len, error,
      error_len));
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (out_required_len == NULL) {
    proton_engine_set_message(error, error_len, "out_required_len is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_dialog_lock();
  proton_engine_dialog_request_t *request =
      proton_engine_dialog_request_find_locked(
          PROTON_ENGINE_DIALOG_OWNER_RUNTIME, (uintptr_t)runtime, dialog);
  if (request == NULL) {
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, "dialog request is unknown");
    return PROTON_ERR_INVALID_HANDLE;
  }
  ProtonRuntimeAlertController *controller =
      request->platform_state != NULL
          ? (ProtonRuntimeAlertController *)request->platform_state
          : nil;
  [controller retain];
  proton_engine_dialog_unlock();
  [controller tick];
  [controller release];
  proton_engine_dialog_lock();
  request = proton_engine_dialog_request_find_locked(
      PROTON_ENGINE_DIALOG_OWNER_RUNTIME, (uintptr_t)runtime, dialog);
  if (request == NULL) {
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, "dialog request is unknown");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (!request->completed) {
    proton_engine_dialog_unlock();
    return PROTON_EVENT_NONE;
  }
  if (request->status != PROTON_OK) {
    int32_t request_status = request->status;
    char request_error[sizeof(request->error)];
    snprintf(request_error, sizeof(request_error), "%s", request->error);
    request = proton_engine_dialog_request_remove_locked(
        PROTON_ENGINE_DIALOG_OWNER_RUNTIME, (uintptr_t)runtime, dialog);
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, request_error);
    proton_engine_dialog_request_release(request);
    return request_status;
  }
  const char *result = request->result != NULL ? request->result : "";
  int32_t required = (int32_t)strlen(result) + 1;
  *out_required_len = required;
  if (buffer == NULL || buffer_len < required) {
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, "dialog result buffer too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, result, (size_t)required);
  request = proton_engine_dialog_request_remove_locked(
      PROTON_ENGINE_DIALOG_OWNER_RUNTIME, (uintptr_t)runtime, dialog);
  proton_engine_dialog_unlock();
  proton_engine_dialog_request_release(request);
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
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_window_begin_message_dialog(
      window, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len));
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
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse returnCode) {
                        (void)returnCode;
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
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_window_begin_confirm_dialog(
      window, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len));
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
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse returnCode) {
                        const char *result =
                            returnCode == NSAlertFirstButtonReturn ? "1" : "0";
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
        [panel beginSheetModalForWindow:parent
                      completionHandler:^(NSModalResponse returnCode) {
                        NSString *result = @"";
                        if (returnCode == NSModalResponseOK &&
                            [panel URL] != nil) {
                          result = [[panel URL] path] ?: @"";
                        }
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
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_window_begin_open_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len, out_dialog, error,
      error_len));
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
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_window_begin_save_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len, out_dialog, error,
      error_len));
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
  PROTON_DIALOG_RETURN_ON_MAIN(
      proton_engine_window_begin_choose_directory_dialog(
          window, title_utf8, title_len, path_utf8, path_len, out_dialog,
          error, error_len));
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_FILE_DIALOG_CHOOSE_DIRECTORY, out_dialog, error,
      error_len);
}

int32_t proton_engine_window_poll_dialog_result(
    proton_engine_window_t *window,
    int64_t dialog,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len) {
  PROTON_DIALOG_RETURN_ON_MAIN(proton_engine_window_poll_dialog_result(
      window, dialog, buffer, buffer_len, out_required_len, error,
      error_len));
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (out_required_len == NULL) {
    proton_engine_set_message(error, error_len, "out_required_len is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  proton_engine_dialog_lock();
  proton_engine_dialog_request_t *request =
      proton_engine_dialog_request_find_locked(
          PROTON_ENGINE_DIALOG_OWNER_WINDOW,
          (uintptr_t)proton_engine_window_native_id(window), dialog);
  if (request == NULL) {
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, "dialog request is unknown");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (!request->completed) {
    proton_engine_dialog_unlock();
    return PROTON_EVENT_NONE;
  }
  if (request->status != PROTON_OK) {
    int32_t status = request->status;
    char request_error[sizeof(request->error)];
    snprintf(request_error, sizeof(request_error), "%s", request->error);
    request = proton_engine_dialog_request_remove_locked(
        PROTON_ENGINE_DIALOG_OWNER_WINDOW,
        (uintptr_t)proton_engine_window_native_id(window), dialog);
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, request_error);
    proton_engine_dialog_request_release(request);
    return status;
  }
  const char *result = request->result != NULL ? request->result : "";
  int32_t required = (int32_t)strlen(result) + 1;
  *out_required_len = required;
  if (buffer == NULL || buffer_len < required) {
    proton_engine_dialog_unlock();
    proton_engine_set_message(error, error_len, "dialog result buffer too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, result, (size_t)required);
  request = proton_engine_dialog_request_remove_locked(
      PROTON_ENGINE_DIALOG_OWNER_WINDOW,
      (uintptr_t)proton_engine_window_native_id(window), dialog);
  proton_engine_dialog_unlock();
  proton_engine_dialog_request_release(request);
  return PROTON_OK;
}
