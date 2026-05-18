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
