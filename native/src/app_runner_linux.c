#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include "app_runner.h"

#include "proton_engine.h"

#include <glib.h>

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

typedef enum {
  PROTON_APP_RUNNER_IDLE = 0,
  PROTON_APP_RUNNER_STARTING,
  PROTON_APP_RUNNER_ENGINE_LOOP,
  PROTON_APP_RUNNER_STOPPING,
} proton_app_runner_phase_t;

typedef enum {
  PROTON_APP_WORK_INT = 0,
  PROTON_APP_WORK_U64,
  PROTON_APP_WORK_VOID,
} proton_app_work_kind_t;

typedef struct {
  proton_app_work_kind_t kind;
  union {
    proton_app_main_int_work_t int_work;
    proton_app_main_u64_work_t u64_work;
    proton_app_main_void_work_t void_work;
  } callback;
  void *context;
  pthread_mutex_t lock;
  pthread_cond_t condition;
  bool initialized;
  bool completed;
  int32_t int_result;
  uint64_t u64_result;
} proton_app_dispatch_request_t;

typedef struct {
  proton_app_entry_t entry;
} proton_app_worker_context_t;

static atomic_bool g_proton_app_runner_active = ATOMIC_VAR_INIT(false);
static atomic_bool g_proton_app_worker_finished = ATOMIC_VAR_INIT(false);
static atomic_bool g_proton_engine_loop_running = ATOMIC_VAR_INIT(false);
static pthread_t g_proton_app_ui_thread;
static bool g_proton_app_ui_thread_set = false;
static GMainContext *g_proton_app_main_context = NULL;
static GMainLoop *g_proton_app_phase_loop = NULL;
static proton_app_runner_phase_t g_proton_app_runner_phase =
    PROTON_APP_RUNNER_IDLE;
static proton_app_dispatch_request_t *g_proton_app_engine_start = NULL;

static bool proton_app_is_process_main_thread(void) {
  return (pid_t)syscall(SYS_gettid) == getpid();
}

bool proton_app_runner_is_active(void) {
  return atomic_load_explicit(&g_proton_app_runner_active,
                              memory_order_acquire);
}

bool proton_app_runner_engine_loop_is_running(void) {
  return atomic_load_explicit(&g_proton_engine_loop_running,
                              memory_order_acquire);
}

bool proton_app_runner_is_ui_thread(void) {
  return proton_app_runner_is_active() && g_proton_app_ui_thread_set &&
         pthread_equal(pthread_self(), g_proton_app_ui_thread) != 0;
}

static bool proton_app_init_request(proton_app_dispatch_request_t *request,
                                    proton_app_work_kind_t kind,
                                    void *context) {
  memset(request, 0, sizeof(*request));
  request->kind = kind;
  request->context = context;
  request->int_result = PROTON_ERR_PLATFORM;
  if (pthread_mutex_init(&request->lock, NULL) != 0) {
    return false;
  }
  if (pthread_cond_init(&request->condition, NULL) != 0) {
    pthread_mutex_destroy(&request->lock);
    return false;
  }
  request->initialized = true;
  return true;
}

static void proton_app_dispose_request(
    proton_app_dispatch_request_t *request) {
  if (request == NULL || !request->initialized) {
    return;
  }
  pthread_cond_destroy(&request->condition);
  pthread_mutex_destroy(&request->lock);
  request->initialized = false;
}

static void proton_app_complete_request(
    proton_app_dispatch_request_t *request) {
  if (request == NULL || !request->initialized) {
    return;
  }
  pthread_mutex_lock(&request->lock);
  request->completed = true;
  pthread_cond_signal(&request->condition);
  pthread_mutex_unlock(&request->lock);
}

static void proton_app_wait_request(proton_app_dispatch_request_t *request) {
  pthread_mutex_lock(&request->lock);
  while (!request->completed) {
    pthread_cond_wait(&request->condition, &request->lock);
  }
  pthread_mutex_unlock(&request->lock);
}

static bool proton_app_post_source(GSourceFunc callback, void *context) {
  if (callback == NULL || g_proton_app_main_context == NULL) {
    return false;
  }
  GSource *source = g_idle_source_new();
  if (source == NULL) {
    return false;
  }
  g_source_set_priority(source, G_PRIORITY_DEFAULT);
  g_source_set_callback(source, callback, context, NULL);
  guint source_id = g_source_attach(source, g_proton_app_main_context);
  g_source_unref(source);
  return source_id != 0;
}

static gboolean proton_app_execute_request(void *raw_request) {
  proton_app_dispatch_request_t *request =
      (proton_app_dispatch_request_t *)raw_request;
  if (request == NULL) {
    return G_SOURCE_REMOVE;
  }
  switch (request->kind) {
  case PROTON_APP_WORK_INT:
    request->int_result = request->callback.int_work(request->context);
    break;
  case PROTON_APP_WORK_U64:
    request->u64_result = request->callback.u64_work(request->context);
    break;
  case PROTON_APP_WORK_VOID:
    request->callback.void_work(request->context);
    break;
  }
  proton_app_complete_request(request);
  return G_SOURCE_REMOVE;
}

int32_t proton_app_dispatch_sync_int(proton_app_main_int_work_t work,
                                     void *context) {
  if (work == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (proton_app_runner_is_ui_thread()) {
    return work(context);
  }
  if (!proton_app_runner_is_active()) {
    return PROTON_ERR_WRONG_THREAD;
  }
  proton_app_dispatch_request_t request;
  if (!proton_app_init_request(&request, PROTON_APP_WORK_INT, context)) {
    return PROTON_ERR_PLATFORM;
  }
  request.callback.int_work = work;
  if (!proton_app_post_source(proton_app_execute_request, &request)) {
    proton_app_dispose_request(&request);
    return PROTON_ERR_PLATFORM;
  }
  proton_app_wait_request(&request);
  int32_t result = request.int_result;
  proton_app_dispose_request(&request);
  return result;
}

uint64_t proton_app_dispatch_sync_u64(proton_app_main_u64_work_t work,
                                      void *context) {
  if (work == NULL) {
    return 0;
  }
  if (proton_app_runner_is_ui_thread()) {
    return work(context);
  }
  if (!proton_app_runner_is_active()) {
    return 0;
  }
  proton_app_dispatch_request_t request;
  if (!proton_app_init_request(&request, PROTON_APP_WORK_U64, context)) {
    return 0;
  }
  request.callback.u64_work = work;
  if (!proton_app_post_source(proton_app_execute_request, &request)) {
    proton_app_dispose_request(&request);
    return 0;
  }
  proton_app_wait_request(&request);
  uint64_t result = request.u64_result;
  proton_app_dispose_request(&request);
  return result;
}

void proton_app_dispatch_sync_void(proton_app_main_void_work_t work,
                                   void *context) {
  if (work == NULL) {
    return;
  }
  if (proton_app_runner_is_ui_thread()) {
    work(context);
    return;
  }
  if (!proton_app_runner_is_active()) {
    return;
  }
  proton_app_dispatch_request_t request;
  if (!proton_app_init_request(&request, PROTON_APP_WORK_VOID, context)) {
    return;
  }
  request.callback.void_work = work;
  if (proton_app_post_source(proton_app_execute_request, &request)) {
    proton_app_wait_request(&request);
  }
  proton_app_dispose_request(&request);
}

static gboolean proton_app_accept_engine_start(void *raw_request) {
  proton_app_dispatch_request_t *request =
      (proton_app_dispatch_request_t *)raw_request;
  if (g_proton_app_runner_phase != PROTON_APP_RUNNER_STARTING ||
      g_proton_app_engine_start != NULL) {
    request->int_result = PROTON_ERR_ALREADY_INITIALIZED;
    proton_app_complete_request(request);
    return G_SOURCE_REMOVE;
  }
  g_proton_app_engine_start = request;
  if (g_proton_app_phase_loop != NULL) {
    g_main_loop_quit(g_proton_app_phase_loop);
  }
  return G_SOURCE_REMOVE;
}

int32_t proton_app_dispatch_engine_start(proton_app_main_int_work_t work,
                                         void *context) {
  if (work == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (proton_app_runner_is_ui_thread()) {
    return work(context);
  }
  if (!proton_app_runner_is_active()) {
    return PROTON_ERR_WRONG_THREAD;
  }
  proton_app_dispatch_request_t request;
  if (!proton_app_init_request(&request, PROTON_APP_WORK_INT, context)) {
    return PROTON_ERR_PLATFORM;
  }
  request.callback.int_work = work;
  if (!proton_app_post_source(proton_app_accept_engine_start, &request)) {
    proton_app_dispose_request(&request);
    return PROTON_ERR_PLATFORM;
  }
  proton_app_wait_request(&request);
  int32_t result = request.int_result;
  proton_app_dispose_request(&request);
  return result;
}

static gboolean proton_app_handle_worker_finished(void *unused) {
  (void)unused;
  atomic_store_explicit(&g_proton_app_worker_finished, true,
                        memory_order_release);
  if (g_proton_app_runner_phase == PROTON_APP_RUNNER_ENGINE_LOOP) {
    proton_engine_quit_app_loop();
  } else if (g_proton_app_phase_loop != NULL) {
    g_main_loop_quit(g_proton_app_phase_loop);
  }
  return G_SOURCE_REMOVE;
}

static void *proton_app_worker_main(void *raw_context) {
  proton_app_worker_context_t *context =
      (proton_app_worker_context_t *)raw_context;
  context->entry();
  if (!proton_app_post_source(proton_app_handle_worker_finished, NULL)) {
    atomic_store_explicit(&g_proton_app_worker_finished, true,
                          memory_order_release);
  }
  return NULL;
}

static void proton_app_reset_runner(void) {
  if (g_proton_app_phase_loop != NULL) {
    g_main_loop_unref(g_proton_app_phase_loop);
    g_proton_app_phase_loop = NULL;
  }
  if (g_proton_app_main_context != NULL) {
    g_main_context_unref(g_proton_app_main_context);
    g_proton_app_main_context = NULL;
  }
  g_proton_app_engine_start = NULL;
  g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
  g_proton_app_ui_thread_set = false;
  atomic_store_explicit(&g_proton_engine_loop_running, false,
                        memory_order_release);
  atomic_store_explicit(&g_proton_app_runner_active, false,
                        memory_order_release);
}

int32_t proton_app_run(proton_app_entry_t entry) {
  if (entry == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "application entry is required");
  }
  if (!proton_app_is_process_main_thread()) {
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

  g_proton_app_ui_thread = pthread_self();
  g_proton_app_ui_thread_set = true;
  g_proton_app_runner_phase = PROTON_APP_RUNNER_STARTING;
  g_proton_app_engine_start = NULL;
  atomic_store_explicit(&g_proton_app_worker_finished, false,
                        memory_order_release);
  atomic_store_explicit(&g_proton_engine_loop_running, false,
                        memory_order_release);
  g_proton_app_main_context = g_main_context_ref(g_main_context_default());
  g_proton_app_phase_loop =
      g_main_loop_new(g_proton_app_main_context, FALSE);
  if (g_proton_app_phase_loop == NULL) {
    proton_app_reset_runner();
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to create application main loop");
  }

  char engine_error[512] = {0};
  int32_t status =
      proton_engine_prepare_app(engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    proton_app_reset_runner();
    return proton_set_engine_status(status, engine_error);
  }

  proton_app_worker_context_t context = {.entry = entry};
  pthread_t worker;
  if (pthread_create(&worker, NULL, proton_app_worker_main, &context) != 0) {
    char finish_error[512] = {0};
    (void)proton_engine_finish_app(finish_error, sizeof(finish_error));
    proton_app_reset_runner();
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to create application thread");
  }

  while (!atomic_load_explicit(&g_proton_app_worker_finished,
                               memory_order_acquire)) {
    if (g_proton_app_engine_start == NULL) {
      g_main_loop_run(g_proton_app_phase_loop);
    }
    if (atomic_load_explicit(&g_proton_app_worker_finished,
                             memory_order_acquire)) {
      break;
    }
    proton_app_dispatch_request_t *engine_start = g_proton_app_engine_start;
    g_proton_app_engine_start = NULL;
    if (engine_start == NULL) {
      continue;
    }
    int32_t start_status =
        engine_start->callback.int_work(engine_start->context);
    engine_start->int_result = start_status;
    if (start_status != PROTON_OK) {
      proton_app_complete_request(engine_start);
      continue;
    }
    g_proton_app_runner_phase = PROTON_APP_RUNNER_ENGINE_LOOP;
    atomic_store_explicit(&g_proton_engine_loop_running, true,
                          memory_order_release);
    proton_app_complete_request(engine_start);
    status = proton_engine_run_app_loop(engine_error, sizeof(engine_error));
    atomic_store_explicit(&g_proton_engine_loop_running, false,
                          memory_order_release);
    break;
  }

  g_proton_app_runner_phase = PROTON_APP_RUNNER_STOPPING;
  while (!atomic_load_explicit(&g_proton_app_worker_finished,
                               memory_order_acquire)) {
    g_main_loop_run(g_proton_app_phase_loop);
  }

  int join_status = pthread_join(worker, NULL);
  char finish_error[512] = {0};
  int32_t finish_status =
      proton_engine_finish_app(finish_error, sizeof(finish_error));
  proton_app_reset_runner();
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
