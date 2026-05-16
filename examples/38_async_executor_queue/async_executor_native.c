#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

typedef void (*lepus_example_call_closure_t)(void *closure);

struct lepus_example_task {
  int32_t id;
  int32_t steps;
  int32_t stop;
  char *label;
  struct lepus_example_task *next;
};

struct lepus_example_task_queue {
#ifdef _WIN32
  CRITICAL_SECTION lock;
  CONDITION_VARIABLE ready;
#else
  pthread_mutex_t lock;
  pthread_cond_t ready;
#endif
  int32_t closed;
  struct lepus_example_task *head;
  struct lepus_example_task *tail;
};

struct lepus_example_runner {
  lepus_example_call_closure_t call_closure;
  void *closure;
};

static char *lepus_example_strdup(const char *value) {
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

static void lepus_example_task_free(struct lepus_example_task *task) {
  if (task == NULL) {
    return;
  }
  free(task->label);
  free(task);
}

static struct lepus_example_task *lepus_example_task_new_stop(void) {
  struct lepus_example_task *task =
      (struct lepus_example_task *)calloc(1, sizeof(*task));
  if (task != NULL) {
    task->stop = 1;
  }
  return task;
}

static void lepus_example_queue_lock(struct lepus_example_task_queue *queue) {
#ifdef _WIN32
  EnterCriticalSection(&queue->lock);
#else
  pthread_mutex_lock(&queue->lock);
#endif
}

static void lepus_example_queue_unlock(struct lepus_example_task_queue *queue) {
#ifdef _WIN32
  LeaveCriticalSection(&queue->lock);
#else
  pthread_mutex_unlock(&queue->lock);
#endif
}

static void lepus_example_queue_wait(struct lepus_example_task_queue *queue) {
#ifdef _WIN32
  SleepConditionVariableCS(&queue->ready, &queue->lock, INFINITE);
#else
  pthread_cond_wait(&queue->ready, &queue->lock);
#endif
}

static void lepus_example_queue_signal(struct lepus_example_task_queue *queue) {
#ifdef _WIN32
  WakeConditionVariable(&queue->ready);
#else
  pthread_cond_signal(&queue->ready);
#endif
}

static void lepus_example_queue_broadcast(
    struct lepus_example_task_queue *queue) {
#ifdef _WIN32
  WakeAllConditionVariable(&queue->ready);
#else
  pthread_cond_broadcast(&queue->ready);
#endif
}

static void lepus_example_queue_finalize(void *raw_queue) {
  struct lepus_example_task_queue *queue =
      (struct lepus_example_task_queue *)raw_queue;
  struct lepus_example_task *task;
  if (queue == NULL) {
    return;
  }
  lepus_example_queue_lock(queue);
  task = queue->head;
  queue->head = NULL;
  queue->tail = NULL;
  queue->closed = 1;
  lepus_example_queue_broadcast(queue);
  lepus_example_queue_unlock(queue);
  while (task != NULL) {
    struct lepus_example_task *next = task->next;
    lepus_example_task_free(task);
    task = next;
  }
#ifdef _WIN32
  DeleteCriticalSection(&queue->lock);
#else
  pthread_cond_destroy(&queue->ready);
  pthread_mutex_destroy(&queue->lock);
#endif
}

#ifdef _WIN32
static DWORD WINAPI lepus_example_runner_main(void *raw_runner) {
#else
static void *lepus_example_runner_main(void *raw_runner) {
#endif
  struct lepus_example_runner *runner =
      (struct lepus_example_runner *)raw_runner;
  runner->call_closure(runner->closure);
  moonbit_decref(runner->closure);
  free(runner);
#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}

MOONBIT_FFI_EXPORT int32_t lepus_example_async_executor_start(
    lepus_example_call_closure_t call_closure,
    void *closure) {
  struct lepus_example_runner *runner =
      (struct lepus_example_runner *)malloc(sizeof(*runner));
  if (runner == NULL) {
    if (closure != NULL) {
      moonbit_decref(closure);
    }
    return 0;
  }
  runner->call_closure = call_closure;
  runner->closure = closure;
#ifdef _WIN32
  {
    HANDLE thread =
        CreateThread(NULL, 0, lepus_example_runner_main, runner, 0, NULL);
    if (thread == NULL) {
      moonbit_decref(closure);
      free(runner);
      return 0;
    }
    CloseHandle(thread);
  }
#else
  {
    pthread_t thread;
    if (pthread_create(&thread, NULL, lepus_example_runner_main, runner) != 0) {
      moonbit_decref(closure);
      free(runner);
      return 0;
    }
    pthread_detach(thread);
  }
#endif
  return 1;
}

MOONBIT_FFI_EXPORT struct lepus_example_task_queue *
lepus_example_task_queue_new(void) {
  struct lepus_example_task_queue *queue =
      (struct lepus_example_task_queue *)moonbit_make_external_object(
          lepus_example_queue_finalize, sizeof(*queue));
  if (queue == NULL) {
    return NULL;
  }
  memset(queue, 0, sizeof(*queue));
#ifdef _WIN32
  InitializeCriticalSection(&queue->lock);
  InitializeConditionVariable(&queue->ready);
#else
  pthread_mutex_init(&queue->lock, NULL);
  pthread_cond_init(&queue->ready, NULL);
#endif
  return queue;
}

MOONBIT_FFI_EXPORT int32_t lepus_example_task_queue_push(
    struct lepus_example_task_queue *queue,
    int32_t id,
    int32_t steps,
    moonbit_bytes_t label) {
  struct lepus_example_task *task;
  if (queue == NULL) {
    return 0;
  }
  task = (struct lepus_example_task *)calloc(1, sizeof(*task));
  if (task == NULL) {
    return 0;
  }
  task->id = id;
  task->steps = steps;
  task->label = lepus_example_strdup((const char *)label);
  if (task->label == NULL) {
    free(task);
    return 0;
  }
  lepus_example_queue_lock(queue);
  if (queue->closed) {
    lepus_example_queue_unlock(queue);
    lepus_example_task_free(task);
    return 0;
  }
  if (queue->tail == NULL) {
    queue->head = task;
    queue->tail = task;
  } else {
    queue->tail->next = task;
    queue->tail = task;
  }
  lepus_example_queue_signal(queue);
  lepus_example_queue_unlock(queue);
  return 1;
}

MOONBIT_FFI_EXPORT struct lepus_example_task *
lepus_example_task_queue_pop(struct lepus_example_task_queue *queue) {
  struct lepus_example_task *task;
  if (queue == NULL) {
    return lepus_example_task_new_stop();
  }
  lepus_example_queue_lock(queue);
  while (queue->head == NULL && !queue->closed) {
    lepus_example_queue_wait(queue);
  }
  if (queue->head == NULL && queue->closed) {
    lepus_example_queue_unlock(queue);
    return lepus_example_task_new_stop();
  }
  task = queue->head;
  queue->head = task->next;
  if (queue->head == NULL) {
    queue->tail = NULL;
  }
  task->next = NULL;
  lepus_example_queue_unlock(queue);
  return task;
}

MOONBIT_FFI_EXPORT void lepus_example_task_queue_close(
    struct lepus_example_task_queue *queue) {
  if (queue == NULL) {
    return;
  }
  lepus_example_queue_lock(queue);
  queue->closed = 1;
  lepus_example_queue_broadcast(queue);
  lepus_example_queue_unlock(queue);
}

MOONBIT_FFI_EXPORT int32_t lepus_example_task_is_stop(
    struct lepus_example_task *task) {
  return task == NULL || task->stop != 0;
}

MOONBIT_FFI_EXPORT int32_t lepus_example_task_id(
    struct lepus_example_task *task) {
  return task == NULL ? 0 : task->id;
}

MOONBIT_FFI_EXPORT int32_t lepus_example_task_steps(
    struct lepus_example_task *task) {
  return task == NULL ? 0 : task->steps;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t lepus_example_task_label(
    struct lepus_example_task *task) {
  const char *label = task == NULL || task->label == NULL ? "" : task->label;
  size_t len = strlen(label) + 1;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)len);
  memcpy(bytes, label, len);
  return bytes;
}

MOONBIT_FFI_EXPORT void lepus_example_task_destroy(
    struct lepus_example_task *task) {
  lepus_example_task_free(task);
}
