#include "app_runner.h"

#include "proton_engine.h"

#import <AppKit/AppKit.h>

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>

typedef struct {
  proton_app_entry_t entry;
} proton_app_worker_context_t;

static atomic_bool g_proton_app_runner_active = ATOMIC_VAR_INIT(false);

bool proton_app_runner_is_active(void) {
  return atomic_load_explicit(&g_proton_app_runner_active,
                              memory_order_acquire);
}

int32_t proton_app_dispatch_sync_int(proton_app_main_int_work_t work) {
  if (work == nil) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (pthread_main_np()) {
    return work();
  }
  if (!proton_app_runner_is_active()) {
    return PROTON_ERR_WRONG_THREAD;
  }
  __block int32_t result = PROTON_ERR_PLATFORM;
  dispatch_sync(dispatch_get_main_queue(), ^{
    @autoreleasepool {
      result = work();
    }
  });
  return result;
}

uint64_t proton_app_dispatch_sync_u64(proton_app_main_u64_work_t work) {
  if (work == nil) {
    return 0;
  }
  if (pthread_main_np()) {
    return work();
  }
  if (!proton_app_runner_is_active()) {
    return 0;
  }
  __block uint64_t result = 0;
  dispatch_sync(dispatch_get_main_queue(), ^{
    @autoreleasepool {
      result = work();
    }
  });
  return result;
}

void proton_app_dispatch_sync_void(proton_app_main_void_work_t work) {
  if (work == nil) {
    return;
  }
  if (pthread_main_np()) {
    work();
    return;
  }
  if (!proton_app_runner_is_active()) {
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    @autoreleasepool {
      work();
    }
  });
}

static void proton_app_stop_main_loop(void) {
  [NSApp stop:nil];
  NSEvent *wake_event =
      [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                         location:NSZeroPoint
                    modifierFlags:0
                        timestamp:0
                     windowNumber:0
                          context:nil
                          subtype:0
                            data1:0
                            data2:0];
  [NSApp postEvent:wake_event atStart:NO];
}

static void *proton_app_worker_main(void *raw_context) {
  @autoreleasepool {
    proton_app_worker_context_t *context =
        (proton_app_worker_context_t *)raw_context;
    context->entry();
    dispatch_async(dispatch_get_main_queue(), ^{
      proton_app_stop_main_loop();
    });
  }
  return NULL;
}

int32_t proton_app_run(proton_app_entry_t entry) {
  if (entry == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "application entry is required");
  }
  if (!pthread_main_np()) {
    return proton_set_error(PROTON_ERR_WRONG_THREAD,
                            "application runner must start on the main thread");
  }
  bool expected = false;
  if (!atomic_compare_exchange_strong_explicit(
          &g_proton_app_runner_active, &expected, true, memory_order_acq_rel,
          memory_order_acquire)) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "application runner is already active");
  }

  char engine_error[512] = {0};
  int32_t status =
      proton_engine_prepare_app(engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    atomic_store_explicit(&g_proton_app_runner_active, false,
                          memory_order_release);
    return proton_set_engine_status(status, engine_error);
  }

  proton_app_worker_context_t context = {.entry = entry};
  pthread_t worker;
  int create_status =
      pthread_create(&worker, NULL, proton_app_worker_main, &context);
  if (create_status != 0) {
    atomic_store_explicit(&g_proton_app_runner_active, false,
                          memory_order_release);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to create application thread");
  }

  [NSApp run];
  int join_status = pthread_join(worker, NULL);
  atomic_store_explicit(&g_proton_app_runner_active, false,
                        memory_order_release);
  if (join_status != 0) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to join application thread");
  }
  return proton_set_error(PROTON_OK, NULL);
}
