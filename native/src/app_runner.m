#include "app_runner.h"

#include "proton_engine.h"

#import <AppKit/AppKit.h>

#include <Block.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>

typedef struct {
  proton_app_entry_t entry;
} proton_app_worker_context_t;

typedef struct {
  proton_app_main_int_work_t work;
  pthread_mutex_t lock;
  pthread_cond_t condition;
  bool completed;
  int32_t result;
} proton_app_engine_start_t;

typedef enum {
  PROTON_APP_RUNNER_IDLE = 0,
  PROTON_APP_RUNNER_STARTING,
  PROTON_APP_RUNNER_ENGINE_LOOP,
  PROTON_APP_RUNNER_STOPPING,
} proton_app_runner_phase_t;

static atomic_bool g_proton_app_runner_active = ATOMIC_VAR_INIT(false);
static atomic_bool g_proton_app_worker_finished = ATOMIC_VAR_INIT(false);
static atomic_bool g_proton_engine_loop_running = ATOMIC_VAR_INIT(false);
static proton_app_runner_phase_t g_proton_app_runner_phase =
    PROTON_APP_RUNNER_IDLE;
static proton_app_engine_start_t *g_proton_app_engine_start = NULL;

bool proton_app_runner_is_active(void) {
  return atomic_load_explicit(&g_proton_app_runner_active,
                              memory_order_acquire);
}

bool proton_app_runner_engine_loop_is_running(void) {
  return atomic_load_explicit(&g_proton_engine_loop_running,
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

static void proton_app_stop_startup_loop(void) {
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

static void proton_app_complete_engine_start(
    proton_app_engine_start_t *request,
    int32_t result) {
  pthread_mutex_lock(&request->lock);
  request->result = result;
  request->completed = true;
  pthread_cond_signal(&request->condition);
  pthread_mutex_unlock(&request->lock);
}

int32_t proton_app_dispatch_engine_start(proton_app_main_int_work_t work) {
  if (work == nil) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (pthread_main_np()) {
    return work();
  }
  if (!proton_app_runner_is_active()) {
    return PROTON_ERR_WRONG_THREAD;
  }

  proton_app_engine_start_t request = {
      .work = Block_copy(work),
      .completed = false,
      .result = PROTON_ERR_PLATFORM,
  };
  if (request.work == nil || pthread_mutex_init(&request.lock, NULL) != 0) {
    if (request.work != nil) {
      Block_release(request.work);
    }
    return PROTON_ERR_PLATFORM;
  }
  if (pthread_cond_init(&request.condition, NULL) != 0) {
    pthread_mutex_destroy(&request.lock);
    Block_release(request.work);
    return PROTON_ERR_PLATFORM;
  }

  proton_app_engine_start_t *request_ptr = &request;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_proton_app_runner_phase != PROTON_APP_RUNNER_STARTING ||
        g_proton_app_engine_start != NULL) {
      proton_app_complete_engine_start(request_ptr,
                                       PROTON_ERR_ALREADY_INITIALIZED);
      return;
    }
    g_proton_app_engine_start = request_ptr;
    proton_app_stop_startup_loop();
  });

  pthread_mutex_lock(&request.lock);
  while (!request.completed) {
    pthread_cond_wait(&request.condition, &request.lock);
  }
  int32_t result = request.result;
  pthread_mutex_unlock(&request.lock);

  pthread_cond_destroy(&request.condition);
  pthread_mutex_destroy(&request.lock);
  Block_release(request.work);
  return result;
}

static void proton_app_request_stop_on_main(void) {
  switch (g_proton_app_runner_phase) {
  case PROTON_APP_RUNNER_STARTING:
    proton_app_stop_startup_loop();
    break;
  case PROTON_APP_RUNNER_ENGINE_LOOP:
    proton_engine_quit_app_loop();
    break;
  case PROTON_APP_RUNNER_STOPPING:
    proton_app_stop_startup_loop();
    break;
  case PROTON_APP_RUNNER_IDLE:
    break;
  }
}

static void *proton_app_worker_main(void *raw_context) {
  @autoreleasepool {
    proton_app_worker_context_t *context =
        (proton_app_worker_context_t *)raw_context;
    context->entry();
    atomic_store_explicit(&g_proton_app_worker_finished, true,
                          memory_order_release);
    dispatch_async(dispatch_get_main_queue(), ^{
      proton_app_request_stop_on_main();
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

  g_proton_app_runner_phase = PROTON_APP_RUNNER_STARTING;
  g_proton_app_engine_start = NULL;
  atomic_store_explicit(&g_proton_app_worker_finished, false,
                        memory_order_release);
  atomic_store_explicit(&g_proton_engine_loop_running, false,
                        memory_order_release);

  proton_app_worker_context_t context = {.entry = entry};
  pthread_t worker;
  int create_status =
      pthread_create(&worker, NULL, proton_app_worker_main, &context);
  if (create_status != 0) {
    g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
    atomic_store_explicit(&g_proton_app_runner_active, false,
                          memory_order_release);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to create application thread");
  }

  while (!atomic_load_explicit(&g_proton_app_worker_finished,
                               memory_order_acquire)) {
    [NSApp run];
    proton_app_engine_start_t *engine_start = g_proton_app_engine_start;
    g_proton_app_engine_start = NULL;
    if (engine_start == NULL) {
      continue;
    }
    int32_t engine_start_status = engine_start->work();
    if (engine_start_status != PROTON_OK) {
      proton_app_complete_engine_start(engine_start, engine_start_status);
      continue;
    }

    g_proton_app_runner_phase = PROTON_APP_RUNNER_ENGINE_LOOP;
    atomic_store_explicit(&g_proton_engine_loop_running, true,
                          memory_order_release);
    proton_app_complete_engine_start(engine_start, PROTON_OK);
    status = proton_engine_run_app_loop(engine_error, sizeof(engine_error));
    atomic_store_explicit(&g_proton_engine_loop_running, false,
                          memory_order_release);
    break;
  }
  g_proton_app_runner_phase = PROTON_APP_RUNNER_STOPPING;
  while (!atomic_load_explicit(&g_proton_app_worker_finished,
                               memory_order_acquire)) {
    // Keep servicing main-queue work until the worker has fully returned.
    // Runtime destruction quits CEF before the MoonBit entry necessarily
    // finishes, and the remaining cleanup may still dispatch to the main
    // thread.
    [NSApp run];
  }
  int join_status = pthread_join(worker, NULL);
  char finish_error[512] = {0};
  int32_t finish_status =
      proton_engine_finish_app(finish_error, sizeof(finish_error));
  g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
  atomic_store_explicit(&g_proton_app_runner_active, false,
                        memory_order_release);
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  if (join_status != 0) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to join application thread");
  }
  if (finish_status != PROTON_OK) {
    return proton_set_engine_status(finish_status, finish_error);
  }
  return proton_set_error(PROTON_OK, NULL);
}
