#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

typedef void (*lepus_core_call_closure_t)(void *closure);
typedef void (*lepus_core_call_ipc_complete_t)(void *closure, void *response);

struct lepus_core_async_task {
  void *closure;
  struct lepus_core_async_task *next;
};

struct lepus_core_async_executor {
  lepus_core_call_closure_t call_closure;
  int32_t worker_count;
  int32_t closed;
  int32_t joined;
  int32_t destroyed;
  struct lepus_core_async_task *head;
  struct lepus_core_async_task *tail;
#ifdef _WIN32
  CRITICAL_SECTION lock;
  CONDITION_VARIABLE ready;
  HANDLE *workers;
#else
  pthread_mutex_t lock;
  pthread_cond_t ready;
  pthread_t *workers;
#endif
};

struct lepus_core_ipc_pending_request {
  int32_t stop;
  char *id;
  char *request;
  void *complete;
  struct lepus_core_ipc_pending_request *next;
};

struct lepus_core_ipc_request_queue {
  lepus_core_call_ipc_complete_t call_complete;
  int32_t closed;
  struct lepus_core_ipc_pending_request *head;
  struct lepus_core_ipc_pending_request *tail;
#ifdef _WIN32
  CRITICAL_SECTION lock;
  CONDITION_VARIABLE ready;
#else
  pthread_mutex_t lock;
  pthread_cond_t ready;
#endif
};

void lepus_core_async_executor_close(
    struct lepus_core_async_executor *executor);

static void lepus_core_async_executor_finalize(void *raw_executor);

static void lepus_core_async_task_free(struct lepus_core_async_task *task) {
  if (task == NULL) {
    return;
  }
  if (task->closure != NULL) {
    moonbit_decref(task->closure);
  }
  free(task);
}

static char *lepus_core_strdup(const char *value) {
  size_t len;
  char *copy;
  if (value == NULL) {
    value = "";
  }
  len = strlen(value) + 1;
  copy = (char *)malloc(len);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, value, len);
  return copy;
}

static void lepus_core_ipc_pending_request_free(
    struct lepus_core_ipc_pending_request *request) {
  if (request == NULL) {
    return;
  }
  free(request->id);
  free(request->request);
  if (request->complete != NULL) {
    moonbit_decref(request->complete);
  }
  free(request);
}

static struct lepus_core_ipc_pending_request *
lepus_core_ipc_pending_request_new_stop(void) {
  struct lepus_core_ipc_pending_request *request =
      (struct lepus_core_ipc_pending_request *)calloc(1, sizeof(*request));
  if (request != NULL) {
    request->stop = 1;
  }
  return request;
}

static void lepus_core_async_executor_lock(
    struct lepus_core_async_executor *executor) {
#ifdef _WIN32
  EnterCriticalSection(&executor->lock);
#else
  pthread_mutex_lock(&executor->lock);
#endif
}

static void lepus_core_async_executor_unlock(
    struct lepus_core_async_executor *executor) {
#ifdef _WIN32
  LeaveCriticalSection(&executor->lock);
#else
  pthread_mutex_unlock(&executor->lock);
#endif
}

static void lepus_core_async_executor_wait(
    struct lepus_core_async_executor *executor) {
#ifdef _WIN32
  SleepConditionVariableCS(&executor->ready, &executor->lock, INFINITE);
#else
  pthread_cond_wait(&executor->ready, &executor->lock);
#endif
}

static void lepus_core_async_executor_signal(
    struct lepus_core_async_executor *executor) {
#ifdef _WIN32
  WakeConditionVariable(&executor->ready);
#else
  pthread_cond_signal(&executor->ready);
#endif
}

static void lepus_core_async_executor_broadcast(
    struct lepus_core_async_executor *executor) {
#ifdef _WIN32
  WakeAllConditionVariable(&executor->ready);
#else
  pthread_cond_broadcast(&executor->ready);
#endif
}

static void lepus_core_ipc_queue_lock(
    struct lepus_core_ipc_request_queue *queue) {
#ifdef _WIN32
  EnterCriticalSection(&queue->lock);
#else
  pthread_mutex_lock(&queue->lock);
#endif
}

static void lepus_core_ipc_queue_unlock(
    struct lepus_core_ipc_request_queue *queue) {
#ifdef _WIN32
  LeaveCriticalSection(&queue->lock);
#else
  pthread_mutex_unlock(&queue->lock);
#endif
}

static void lepus_core_ipc_queue_wait(
    struct lepus_core_ipc_request_queue *queue) {
#ifdef _WIN32
  SleepConditionVariableCS(&queue->ready, &queue->lock, INFINITE);
#else
  pthread_cond_wait(&queue->ready, &queue->lock);
#endif
}

static void lepus_core_ipc_queue_signal(
    struct lepus_core_ipc_request_queue *queue) {
#ifdef _WIN32
  WakeConditionVariable(&queue->ready);
#else
  pthread_cond_signal(&queue->ready);
#endif
}

static void lepus_core_ipc_queue_broadcast(
    struct lepus_core_ipc_request_queue *queue) {
#ifdef _WIN32
  WakeAllConditionVariable(&queue->ready);
#else
  pthread_cond_broadcast(&queue->ready);
#endif
}

static void lepus_core_ipc_request_queue_finalize(void *raw_queue) {
  struct lepus_core_ipc_request_queue *queue =
      (struct lepus_core_ipc_request_queue *)raw_queue;
  struct lepus_core_ipc_pending_request *request;
  if (queue == NULL) {
    return;
  }
  lepus_core_ipc_queue_lock(queue);
  request = queue->head;
  queue->head = NULL;
  queue->tail = NULL;
  queue->closed = 1;
  lepus_core_ipc_queue_broadcast(queue);
  lepus_core_ipc_queue_unlock(queue);
  while (request != NULL) {
    struct lepus_core_ipc_pending_request *next = request->next;
    lepus_core_ipc_pending_request_free(request);
    request = next;
  }
#ifdef _WIN32
  DeleteCriticalSection(&queue->lock);
#else
  pthread_cond_destroy(&queue->ready);
  pthread_mutex_destroy(&queue->lock);
#endif
}

static struct lepus_core_async_task *lepus_core_async_executor_pop(
    struct lepus_core_async_executor *executor) {
  struct lepus_core_async_task *task;
  lepus_core_async_executor_lock(executor);
  while (executor->head == NULL && !executor->closed) {
    lepus_core_async_executor_wait(executor);
  }
  if (executor->head == NULL && executor->closed) {
    lepus_core_async_executor_unlock(executor);
    return NULL;
  }
  task = executor->head;
  executor->head = task->next;
  if (executor->head == NULL) {
    executor->tail = NULL;
  }
  task->next = NULL;
  lepus_core_async_executor_unlock(executor);
  return task;
}

#ifdef _WIN32
static DWORD WINAPI lepus_core_async_worker_main(void *raw_executor) {
#else
static void *lepus_core_async_worker_main(void *raw_executor) {
#endif
  struct lepus_core_async_executor *executor =
      (struct lepus_core_async_executor *)raw_executor;
  for (;;) {
    struct lepus_core_async_task *task = lepus_core_async_executor_pop(executor);
    if (task == NULL) {
      break;
    }
    executor->call_closure(task->closure);
    moonbit_decref(task->closure);
    free(task);
  }
#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}

static void lepus_core_async_executor_finalize(void *raw_executor) {
  struct lepus_core_async_executor *executor =
      (struct lepus_core_async_executor *)raw_executor;
  if (executor == NULL) {
    return;
  }
  if (executor->destroyed) {
    return;
  }
  lepus_core_async_executor_close(executor);
  executor->destroyed = 1;
#ifdef _WIN32
  DeleteCriticalSection(&executor->lock);
#else
  pthread_cond_destroy(&executor->ready);
  pthread_mutex_destroy(&executor->lock);
#endif
  free(executor->workers);
  executor->workers = NULL;
}

void *lepus_core_async_executor_new(
    lepus_core_call_closure_t call_closure,
    int32_t worker_count) {
  struct lepus_core_async_executor *executor;
  int32_t started = 0;
  if (call_closure == NULL) {
    return NULL;
  }
  if (worker_count < 1) {
    worker_count = 1;
  }
  executor = (struct lepus_core_async_executor *)moonbit_make_external_object(
      lepus_core_async_executor_finalize, sizeof(*executor));
  if (executor == NULL) {
    return NULL;
  }
  memset(executor, 0, sizeof(*executor));
  executor->call_closure = call_closure;
  executor->worker_count = worker_count;
#ifdef _WIN32
  InitializeCriticalSection(&executor->lock);
  InitializeConditionVariable(&executor->ready);
  executor->workers = (HANDLE *)calloc((size_t)worker_count, sizeof(HANDLE));
#else
  pthread_mutex_init(&executor->lock, NULL);
  pthread_cond_init(&executor->ready, NULL);
  executor->workers = (pthread_t *)calloc((size_t)worker_count, sizeof(pthread_t));
#endif
  if (executor->workers == NULL) {
    lepus_core_async_executor_finalize(executor);
    return NULL;
  }
  for (started = 0; started < worker_count; started++) {
#ifdef _WIN32
    executor->workers[started] =
        CreateThread(NULL, 0, lepus_core_async_worker_main, executor, 0, NULL);
    if (executor->workers[started] == NULL) {
      break;
    }
#else
    if (pthread_create(&executor->workers[started], NULL,
                       lepus_core_async_worker_main, executor) != 0) {
      break;
    }
#endif
  }
  if (started != worker_count) {
    executor->worker_count = started;
    lepus_core_async_executor_finalize(executor);
    return NULL;
  }
  return executor;
}

int32_t lepus_core_async_executor_submit(
    struct lepus_core_async_executor *executor,
    void *closure) {
  struct lepus_core_async_task *task;
  if (executor == NULL || closure == NULL) {
    if (closure != NULL) {
      moonbit_decref(closure);
    }
    return 0;
  }
  task = (struct lepus_core_async_task *)calloc(1, sizeof(*task));
  if (task == NULL) {
    moonbit_decref(closure);
    return 0;
  }
  task->closure = closure;
  lepus_core_async_executor_lock(executor);
  if (executor->closed) {
    lepus_core_async_executor_unlock(executor);
    lepus_core_async_task_free(task);
    return 0;
  }
  if (executor->tail == NULL) {
    executor->head = task;
    executor->tail = task;
  } else {
    executor->tail->next = task;
    executor->tail = task;
  }
  lepus_core_async_executor_signal(executor);
  lepus_core_async_executor_unlock(executor);
  return 1;
}

void lepus_core_async_executor_close(
    struct lepus_core_async_executor *executor) {
  int32_t i;
  struct lepus_core_async_task *task;
  if (executor == NULL) {
    return;
  }
  lepus_core_async_executor_lock(executor);
  if (executor->joined) {
    lepus_core_async_executor_unlock(executor);
    return;
  }
  executor->closed = 1;
  lepus_core_async_executor_broadcast(executor);
  lepus_core_async_executor_unlock(executor);

  for (i = 0; i < executor->worker_count; i++) {
#ifdef _WIN32
    WaitForSingleObject(executor->workers[i], INFINITE);
    CloseHandle(executor->workers[i]);
    executor->workers[i] = NULL;
#else
    pthread_join(executor->workers[i], NULL);
#endif
  }

  lepus_core_async_executor_lock(executor);
  executor->joined = 1;
  task = executor->head;
  executor->head = NULL;
  executor->tail = NULL;
  lepus_core_async_executor_unlock(executor);
  while (task != NULL) {
    struct lepus_core_async_task *next = task->next;
    lepus_core_async_task_free(task);
    task = next;
  }
}

void *lepus_core_ipc_request_queue_new(
    lepus_core_call_ipc_complete_t call_complete) {
  struct lepus_core_ipc_request_queue *queue;
  if (call_complete == NULL) {
    return NULL;
  }
  queue = (struct lepus_core_ipc_request_queue *)moonbit_make_external_object(
      lepus_core_ipc_request_queue_finalize, sizeof(*queue));
  if (queue == NULL) {
    return NULL;
  }
  memset(queue, 0, sizeof(*queue));
  queue->call_complete = call_complete;
#ifdef _WIN32
  InitializeCriticalSection(&queue->lock);
  InitializeConditionVariable(&queue->ready);
#else
  pthread_mutex_init(&queue->lock, NULL);
  pthread_cond_init(&queue->ready, NULL);
#endif
  return queue;
}

int32_t lepus_core_ipc_request_queue_push(
    struct lepus_core_ipc_request_queue *queue,
    moonbit_bytes_t id,
    moonbit_bytes_t request_json,
    void *complete) {
  struct lepus_core_ipc_pending_request *request;
  if (queue == NULL || complete == NULL) {
    if (complete != NULL) {
      moonbit_decref(complete);
    }
    return 0;
  }
  request =
      (struct lepus_core_ipc_pending_request *)calloc(1, sizeof(*request));
  if (request == NULL) {
    moonbit_decref(complete);
    return 0;
  }
  request->id = lepus_core_strdup((const char *)id);
  request->request = lepus_core_strdup((const char *)request_json);
  request->complete = complete;
  if (request->id == NULL || request->request == NULL) {
    lepus_core_ipc_pending_request_free(request);
    return 0;
  }
  lepus_core_ipc_queue_lock(queue);
  if (queue->closed) {
    lepus_core_ipc_queue_unlock(queue);
    lepus_core_ipc_pending_request_free(request);
    return 0;
  }
  if (queue->tail == NULL) {
    queue->head = request;
    queue->tail = request;
  } else {
    queue->tail->next = request;
    queue->tail = request;
  }
  lepus_core_ipc_queue_signal(queue);
  lepus_core_ipc_queue_unlock(queue);
  return 1;
}

struct lepus_core_ipc_pending_request *lepus_core_ipc_request_queue_pop(
    struct lepus_core_ipc_request_queue *queue) {
  struct lepus_core_ipc_pending_request *request;
  if (queue == NULL) {
    return lepus_core_ipc_pending_request_new_stop();
  }
  lepus_core_ipc_queue_lock(queue);
  while (queue->head == NULL && !queue->closed) {
    lepus_core_ipc_queue_wait(queue);
  }
  if (queue->head == NULL && queue->closed) {
    lepus_core_ipc_queue_unlock(queue);
    return lepus_core_ipc_pending_request_new_stop();
  }
  request = queue->head;
  queue->head = request->next;
  if (queue->head == NULL) {
    queue->tail = NULL;
  }
  request->next = NULL;
  lepus_core_ipc_queue_unlock(queue);
  return request;
}

void lepus_core_ipc_request_queue_close(
    struct lepus_core_ipc_request_queue *queue) {
  if (queue == NULL) {
    return;
  }
  lepus_core_ipc_queue_lock(queue);
  queue->closed = 1;
  lepus_core_ipc_queue_broadcast(queue);
  lepus_core_ipc_queue_unlock(queue);
}

int32_t lepus_core_ipc_pending_request_is_stop(
    struct lepus_core_ipc_pending_request *request) {
  return request == NULL || request->stop != 0;
}

moonbit_bytes_t lepus_core_ipc_pending_request_id(
    struct lepus_core_ipc_pending_request *request) {
  const char *id = request == NULL || request->id == NULL ? "" : request->id;
  size_t len = strlen(id) + 1;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)len);
  memcpy(bytes, id, len);
  return bytes;
}

moonbit_bytes_t lepus_core_ipc_pending_request_json(
    struct lepus_core_ipc_pending_request *request) {
  const char *request_json =
      request == NULL || request->request == NULL ? "" : request->request;
  size_t len = strlen(request_json) + 1;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)len);
  memcpy(bytes, request_json, len);
  return bytes;
}

void lepus_core_ipc_pending_request_complete(
    struct lepus_core_ipc_request_queue *queue,
    struct lepus_core_ipc_pending_request *request,
    void *response) {
  if (queue == NULL || request == NULL || request->complete == NULL) {
    return;
  }
  queue->call_complete(request->complete, response);
}

void lepus_core_ipc_pending_request_destroy(
    struct lepus_core_ipc_pending_request *request) {
  lepus_core_ipc_pending_request_free(request);
}
