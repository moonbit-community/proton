#include "app_runner.h"

#include "proton_engine.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <process.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_APP_RUNNER_WINDOW_CLASS L"ProtonAppRunnerDispatch"
#define PROTON_APP_RUNNER_DISPATCH (WM_APP + 1)
#define PROTON_APP_RUNNER_ENGINE_START (WM_APP + 2)
#define PROTON_APP_RUNNER_WORKER_FINISHED (WM_APP + 3)

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
  HANDLE completed;
  int32_t int_result;
  uint64_t u64_result;
} proton_app_dispatch_request_t;

typedef struct {
  proton_app_entry_t entry;
} proton_app_worker_context_t;

static volatile LONG g_proton_app_runner_active = 0;
static volatile LONG g_proton_app_worker_finished = 0;
static volatile LONG g_proton_engine_loop_running = 0;
static DWORD g_proton_app_ui_thread_id = 0;
static HWND g_proton_app_dispatch_window = NULL;
static proton_app_runner_phase_t g_proton_app_runner_phase =
    PROTON_APP_RUNNER_IDLE;
static proton_app_dispatch_request_t *g_proton_app_engine_start = NULL;

static bool proton_app_atomic_bool(const volatile LONG *value) {
  return InterlockedCompareExchange((volatile LONG *)value, 0, 0) != 0;
}

bool proton_app_runner_is_active(void) {
  return proton_app_atomic_bool(&g_proton_app_runner_active);
}

bool proton_app_runner_engine_loop_is_running(void) {
  return proton_app_atomic_bool(&g_proton_engine_loop_running);
}

bool proton_app_runner_is_ui_thread(void) {
  return proton_app_runner_is_active() &&
         GetCurrentThreadId() == g_proton_app_ui_thread_id;
}

static void proton_app_complete_request(
    proton_app_dispatch_request_t *request) {
  if (request != NULL && request->completed != NULL) {
    SetEvent(request->completed);
  }
}

static void proton_app_execute_request(
    proton_app_dispatch_request_t *request) {
  if (request == NULL) {
    return;
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
}

static LRESULT CALLBACK proton_app_dispatch_window_proc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  (void)window;
  (void)wparam;
  proton_app_dispatch_request_t *request =
      (proton_app_dispatch_request_t *)lparam;
  switch (message) {
  case PROTON_APP_RUNNER_DISPATCH:
    proton_app_execute_request(request);
    return 0;
  case PROTON_APP_RUNNER_ENGINE_START:
    g_proton_app_engine_start = request;
    return 0;
  case PROTON_APP_RUNNER_WORKER_FINISHED:
    InterlockedExchange(&g_proton_app_worker_finished, 1);
    if (g_proton_app_runner_phase == PROTON_APP_RUNNER_ENGINE_LOOP) {
      proton_engine_quit_app_loop();
    }
    return 0;
  default:
    return DefWindowProcW(window, message, wparam, lparam);
  }
}

static bool proton_app_create_dispatch_window(void) {
  WNDCLASSW window_class;
  memset(&window_class, 0, sizeof(window_class));
  window_class.lpfnWndProc = proton_app_dispatch_window_proc;
  window_class.hInstance = GetModuleHandleW(NULL);
  window_class.lpszClassName = PROTON_APP_RUNNER_WINDOW_CLASS;
  ATOM registered = RegisterClassW(&window_class);
  if (registered == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }
  g_proton_app_dispatch_window = CreateWindowExW(
      0, PROTON_APP_RUNNER_WINDOW_CLASS, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
      NULL, GetModuleHandleW(NULL), NULL);
  return g_proton_app_dispatch_window != NULL;
}

static bool proton_app_post_request(UINT message,
                                    proton_app_dispatch_request_t *request) {
  return g_proton_app_dispatch_window != NULL &&
         PostMessageW(g_proton_app_dispatch_window, message, 0,
                      (LPARAM)request) != 0;
}

static bool proton_app_wait_request(proton_app_dispatch_request_t *request) {
  return request->completed != NULL &&
         WaitForSingleObject(request->completed, INFINITE) == WAIT_OBJECT_0;
}

static void proton_app_init_request(proton_app_dispatch_request_t *request,
                                    proton_app_work_kind_t kind,
                                    void *context) {
  memset(request, 0, sizeof(*request));
  request->kind = kind;
  request->context = context;
  request->completed = CreateEventW(NULL, FALSE, FALSE, NULL);
  request->int_result = PROTON_ERR_PLATFORM;
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
  proton_app_init_request(&request, PROTON_APP_WORK_INT, context);
  request.callback.int_work = work;
  if (request.completed == NULL ||
      !proton_app_post_request(PROTON_APP_RUNNER_DISPATCH, &request) ||
      !proton_app_wait_request(&request)) {
    if (request.completed != NULL) {
      CloseHandle(request.completed);
    }
    return PROTON_ERR_PLATFORM;
  }
  CloseHandle(request.completed);
  return request.int_result;
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
  proton_app_init_request(&request, PROTON_APP_WORK_U64, context);
  request.callback.u64_work = work;
  if (request.completed == NULL ||
      !proton_app_post_request(PROTON_APP_RUNNER_DISPATCH, &request) ||
      !proton_app_wait_request(&request)) {
    if (request.completed != NULL) {
      CloseHandle(request.completed);
    }
    return 0;
  }
  CloseHandle(request.completed);
  return request.u64_result;
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
  proton_app_init_request(&request, PROTON_APP_WORK_VOID, context);
  request.callback.void_work = work;
  if (request.completed != NULL &&
      proton_app_post_request(PROTON_APP_RUNNER_DISPATCH, &request) &&
      proton_app_wait_request(&request)) {
    CloseHandle(request.completed);
    return;
  }
  if (request.completed != NULL) {
    CloseHandle(request.completed);
  }
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
  proton_app_init_request(&request, PROTON_APP_WORK_INT, context);
  request.callback.int_work = work;
  if (request.completed == NULL ||
      !proton_app_post_request(PROTON_APP_RUNNER_ENGINE_START, &request) ||
      !proton_app_wait_request(&request)) {
    if (request.completed != NULL) {
      CloseHandle(request.completed);
    }
    return PROTON_ERR_PLATFORM;
  }
  CloseHandle(request.completed);
  return request.int_result;
}

static unsigned __stdcall proton_app_worker_main(void *raw_context) {
  proton_app_worker_context_t *context =
      (proton_app_worker_context_t *)raw_context;
  context->entry();
  proton_app_post_request(PROTON_APP_RUNNER_WORKER_FINISHED, NULL);
  return 0;
}

static int proton_app_get_message(void) {
  MSG message;
  int result = GetMessageW(&message, NULL, 0, 0);
  if (result > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return result;
}

int32_t proton_app_run(proton_app_entry_t entry) {
  if (entry == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "application entry is required");
  }
  if (InterlockedCompareExchange(&g_proton_app_runner_active, 1, 0) != 0) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "application runner is already active");
  }

  g_proton_app_ui_thread_id = GetCurrentThreadId();
  g_proton_app_runner_phase = PROTON_APP_RUNNER_STARTING;
  g_proton_app_engine_start = NULL;
  InterlockedExchange(&g_proton_app_worker_finished, 0);
  InterlockedExchange(&g_proton_engine_loop_running, 0);
  if (!proton_app_create_dispatch_window()) {
    g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
    g_proton_app_ui_thread_id = 0;
    InterlockedExchange(&g_proton_app_runner_active, 0);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to create application dispatch window");
  }

  char engine_error[512] = {0};
  int32_t status =
      proton_engine_prepare_app(engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    DestroyWindow(g_proton_app_dispatch_window);
    g_proton_app_dispatch_window = NULL;
    g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
    g_proton_app_ui_thread_id = 0;
    InterlockedExchange(&g_proton_app_runner_active, 0);
    return proton_set_engine_status(status, engine_error);
  }

  proton_app_worker_context_t context = {.entry = entry};
  uintptr_t worker = _beginthreadex(NULL, 0, proton_app_worker_main, &context,
                                    0, NULL);
  if (worker == 0) {
    char finish_error[512] = {0};
    (void)proton_engine_finish_app(finish_error, sizeof(finish_error));
    DestroyWindow(g_proton_app_dispatch_window);
    g_proton_app_dispatch_window = NULL;
    g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
    g_proton_app_ui_thread_id = 0;
    InterlockedExchange(&g_proton_app_runner_active, 0);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to create application thread");
  }

  while (!proton_app_atomic_bool(&g_proton_app_worker_finished) &&
         g_proton_app_engine_start == NULL) {
    int message_status = proton_app_get_message();
    if (message_status < 0) {
      status = PROTON_ERR_PLATFORM;
      break;
    }
  }

  proton_app_dispatch_request_t *engine_start = g_proton_app_engine_start;
  g_proton_app_engine_start = NULL;
  if (status == PROTON_OK && engine_start != NULL) {
    int32_t start_status =
        engine_start->callback.int_work(engine_start->context);
    if (start_status == PROTON_OK) {
      g_proton_app_runner_phase = PROTON_APP_RUNNER_ENGINE_LOOP;
      InterlockedExchange(&g_proton_engine_loop_running, 1);
    }
    engine_start->int_result = start_status;
    proton_app_complete_request(engine_start);
    if (start_status == PROTON_OK) {
      status = proton_engine_run_app_loop(engine_error, sizeof(engine_error));
      InterlockedExchange(&g_proton_engine_loop_running, 0);
    }
  }

  g_proton_app_runner_phase = PROTON_APP_RUNNER_STOPPING;
  while (!proton_app_atomic_bool(&g_proton_app_worker_finished)) {
    int message_status = proton_app_get_message();
    if (message_status < 0) {
      status = PROTON_ERR_PLATFORM;
      break;
    }
  }

  DWORD join_status = WaitForSingleObject((HANDLE)worker, INFINITE);
  CloseHandle((HANDLE)worker);
  char finish_error[512] = {0};
  int32_t finish_status =
      proton_engine_finish_app(finish_error, sizeof(finish_error));
  DestroyWindow(g_proton_app_dispatch_window);
  g_proton_app_dispatch_window = NULL;
  g_proton_app_runner_phase = PROTON_APP_RUNNER_IDLE;
  g_proton_app_ui_thread_id = 0;
  InterlockedExchange(&g_proton_app_runner_active, 0);
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  if (join_status != WAIT_OBJECT_0) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to join application thread");
  }
  if (finish_status != PROTON_OK) {
    return proton_set_engine_status(finish_status, finish_error);
  }
  return proton_set_error(PROTON_OK, NULL);
}
