#if defined(__APPLE__)

#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>

#include "../ffi/src/proton_internal.h"

#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

typedef struct proton_relaunch_plan {
  char *executable;
  char *arguments;
  int32_t arguments_len;
  struct proton_relaunch_plan *next;
} proton_relaunch_plan_t;

static proton_relaunch_plan_t *g_relaunch_head = NULL;
static proton_relaunch_plan_t *g_relaunch_tail = NULL;

static int proton_app_control_arguments_valid(const char *arguments,
                                              int32_t arguments_len) {
  if (arguments_len < 0 || (arguments == NULL && arguments_len != 0)) {
    return 0;
  }
  return arguments_len == 0 || arguments[arguments_len - 1] == '\0';
}

static char *proton_app_control_copy(const char *value, size_t length) {
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (length > 0) {
    memcpy(copy, value, length);
  }
  copy[length] = '\0';
  return copy;
}

static NSString *proton_app_control_string(const char *value) {
  return value == NULL ? nil : [NSString stringWithUTF8String:value];
}

static int32_t proton_protocol_client_validate(
    const char *scheme, const char *identifier, const char *executable,
    const char *arguments, int32_t arguments_len, int32_t *out_result,
    NSString **out_scheme, NSString **out_identifier) {
  (void)executable;
  (void)arguments;
  if (scheme == NULL || scheme[0] == '\0' || identifier == NULL ||
      identifier[0] == '\0' || out_result == NULL ||
      !proton_app_control_arguments_valid(arguments, arguments_len)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid protocol client operation");
  }
  *out_result = 0;
  NSString *scheme_string = proton_app_control_string(scheme);
  NSString *identifier_string = proton_app_control_string(identifier);
  NSString *bundle_identifier = [[NSBundle mainBundle] bundleIdentifier];
  if (scheme_string == nil || identifier_string == nil) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "protocol client values must be valid UTF-8");
  }
  if (bundle_identifier == nil ||
      ![bundle_identifier isEqualToString:identifier_string]) {
    return proton_set_error(
        PROTON_ERR_PLATFORM,
        "protocol registration requires a packaged macOS application");
  }
  BOOL declared = NO;
  id url_types = [[[NSBundle mainBundle] infoDictionary]
      objectForKey:@"CFBundleURLTypes"];
  if ([url_types isKindOfClass:[NSArray class]]) {
    for (id url_type in (NSArray *)url_types) {
      if (![url_type isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      id schemes = [(NSDictionary *)url_type objectForKey:@"CFBundleURLSchemes"];
      if ([schemes isKindOfClass:[NSArray class]] &&
          [(NSArray *)schemes containsObject:scheme_string]) {
        declared = YES;
        break;
      }
    }
  }
  if (!declared) {
    return proton_set_error(
        PROTON_ERR_PLATFORM,
        "protocol scheme is missing from the packaged CFBundleURLTypes");
  }
  *out_scheme = scheme_string;
  *out_identifier = identifier_string;
  return PROTON_OK;
}

int32_t proton_protocol_client_set(const char *scheme, const char *identifier,
                                   const char *executable,
                                   const char *arguments,
                                   int32_t arguments_len,
                                   int32_t *out_changed) {
  @autoreleasepool {
    NSString *scheme_string = nil;
    NSString *identifier_string = nil;
    int32_t status = proton_protocol_client_validate(
        scheme, identifier, executable, arguments, arguments_len, out_changed,
        &scheme_string, &identifier_string);
    if (status != PROTON_OK) {
      return status;
    }
    OSStatus result = LSSetDefaultHandlerForURLScheme(
        (__bridge CFStringRef)scheme_string,
        (__bridge CFStringRef)identifier_string);
    if (result != noErr) {
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "Launch Services rejected the protocol handler");
    }
    *out_changed = 1;
    return proton_set_error(PROTON_OK, NULL);
  }
}

int32_t proton_protocol_client_is_default(
    const char *scheme, const char *identifier, const char *executable,
    const char *arguments, int32_t arguments_len, int32_t *out_is_default) {
  @autoreleasepool {
    NSString *scheme_string = nil;
    NSString *identifier_string = nil;
    int32_t status = proton_protocol_client_validate(
        scheme, identifier, executable, arguments, arguments_len,
        out_is_default, &scheme_string, &identifier_string);
    if (status != PROTON_OK) {
      return status;
    }
    NSURL *protocol_url =
        [NSURL URLWithString:[scheme_string stringByAppendingString:@":"]];
    NSURL *application_url = protocol_url == nil
                                 ? nil
                                 : [[NSWorkspace sharedWorkspace]
                                       URLForApplicationToOpenURL:protocol_url];
    NSString *handler = application_url == nil
                            ? nil
                            : [[NSBundle bundleWithURL:application_url]
                                  bundleIdentifier];
    if (handler != nil) {
      *out_is_default = [handler isEqualToString:identifier_string];
    }
    return proton_set_error(PROTON_OK, NULL);
  }
}

int32_t proton_protocol_client_remove(
    const char *scheme, const char *identifier, const char *executable,
    const char *arguments, int32_t arguments_len, int32_t *out_removed) {
  @autoreleasepool {
    NSString *scheme_string = nil;
    NSString *identifier_string = nil;
    int32_t status = proton_protocol_client_validate(
        scheme, identifier, executable, arguments, arguments_len, out_removed,
        &scheme_string, &identifier_string);
    if (status != PROTON_OK) {
      return status;
    }
    int32_t is_default = 0;
    status = proton_protocol_client_is_default(
        scheme, identifier, executable, arguments, arguments_len, &is_default);
    if (status != PROTON_OK || !is_default) {
      return status;
    }
    NSURL *protocol_url =
        [NSURL URLWithString:[scheme_string stringByAppendingString:@":"]];
    if (protocol_url == nil) {
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "cannot construct the protocol URL");
    }
    NSString *replacement = nil;
    for (NSURL *application_url in
         [[NSWorkspace sharedWorkspace]
             URLsForApplicationsToOpenURL:protocol_url]) {
      NSString *candidate =
          [[NSBundle bundleWithURL:application_url] bundleIdentifier];
      if (candidate != nil &&
          ![candidate isEqualToString:identifier_string]) {
        replacement = candidate;
        break;
      }
    }
    if (replacement == nil) {
      replacement = @"None";
    }
    OSStatus result = LSSetDefaultHandlerForURLScheme(
        (__bridge CFStringRef)scheme_string,
        (__bridge CFStringRef)replacement);
    if (result != noErr) {
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "Launch Services rejected protocol removal");
    }
    *out_removed = 1;
    return proton_set_error(PROTON_OK, NULL);
  }
}

int32_t proton_process_schedule_relaunch(const char *executable,
                                         const char *arguments,
                                         int32_t arguments_len) {
  if (executable == NULL || executable[0] == '\0' ||
      !proton_app_control_arguments_valid(arguments, arguments_len)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid relaunch command");
  }
  proton_relaunch_plan_t *plan =
      (proton_relaunch_plan_t *)calloc(1, sizeof(*plan));
  if (plan == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate relaunch plan");
  }
  plan->executable = proton_app_control_copy(executable, strlen(executable));
  plan->arguments =
      proton_app_control_copy(arguments_len == 0 ? "" : arguments,
                              (size_t)arguments_len);
  plan->arguments_len = arguments_len;
  if (plan->executable == NULL || plan->arguments == NULL) {
    free(plan->executable);
    free(plan->arguments);
    free(plan);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to copy relaunch plan");
  }
  if (g_relaunch_tail == NULL) {
    g_relaunch_head = plan;
  } else {
    g_relaunch_tail->next = plan;
  }
  g_relaunch_tail = plan;
  return proton_set_error(PROTON_OK, NULL);
}

static char **proton_process_argv(const proton_relaunch_plan_t *plan) {
  size_t count = 1;
  for (int32_t index = 0; index < plan->arguments_len; index++) {
    if (plan->arguments[index] == '\0') {
      count++;
    }
  }
  char **argv = (char **)calloc(count + 1, sizeof(char *));
  if (argv == NULL) {
    return NULL;
  }
  argv[0] = plan->executable;
  size_t position = 1;
  for (int32_t offset = 0; offset < plan->arguments_len;) {
    argv[position++] = plan->arguments + offset;
    offset += (int32_t)strlen(plan->arguments + offset) + 1;
  }
  return argv;
}

int32_t proton_process_run_relaunches(void) {
  int32_t first_error = PROTON_OK;
  while (g_relaunch_head != NULL) {
    proton_relaunch_plan_t *plan = g_relaunch_head;
    g_relaunch_head = plan->next;
    char **argv = proton_process_argv(plan);
    pid_t child = 0;
    if (argv == NULL ||
        posix_spawn(&child, plan->executable, NULL, NULL, argv, environ) != 0) {
      if (first_error == PROTON_OK) {
        first_error = proton_set_error(
            PROTON_ERR_PLATFORM,
            "failed to start the relaunched application");
      }
    }
    free(argv);
    free(plan->executable);
    free(plan->arguments);
    free(plan);
  }
  g_relaunch_tail = NULL;
  return first_error == PROTON_OK ? proton_set_error(PROTON_OK, NULL)
                                  : first_error;
}

void proton_process_exit(int32_t exit_code) {
  (void)proton_process_run_relaunches();
  _exit(exit_code);
}

#endif
