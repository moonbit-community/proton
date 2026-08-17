#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "proton_app_instance.h"

#include "proton_internal.h"
#include "proton_event.h"
#include "proton_json.h"
#include "proton_state.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <sddl.h>
#include <windows.h>
#else
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#endif

#define PROTON_APP_INSTANCE_CAPACITY 8
#define PROTON_APP_INSTANCE_EVENT_CAPACITY 32
#define PROTON_APP_INSTANCE_MAX_MESSAGE_BYTES (PROTON_MAX_EVENT_BYTES - 128)
#define PROTON_APP_INSTANCE_HANDLE_TYPE 3ULL
#define PROTON_APP_INSTANCE_HANDLE_TYPE_SHIFT 60
#define PROTON_APP_INSTANCE_HANDLE_GENERATION_SHIFT 32
#define PROTON_APP_INSTANCE_HANDLE_INDEX_MASK 0xffffffffULL

typedef struct {
  uint32_t generation;
  bool occupied;
  bool destroyed;
  bool owns_endpoint;
  proton_event_t *events[PROTON_APP_INSTANCE_EVENT_CAPACITY];
  uint32_t event_head;
  uint32_t event_count;
  proton_engine_runtime_t *runtime;
#ifdef _WIN32
  CRITICAL_SECTION lock;
  bool lock_initialized;
  HANDLE mutex;
  HANDLE thread;
  HANDLE stop_event;
  PSECURITY_DESCRIPTOR security_descriptor;
  wchar_t pipe_name[128];
#else
  pthread_mutex_t lock;
  bool lock_initialized;
  pthread_t thread;
  bool thread_started;
  atomic_bool stopping;
  int ownership_fd;
  int listen_fd;
  int client_fd;
  char ownership_path[256];
  char socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
#endif
} proton_app_instance_slot_t;

typedef struct {
  const proton_json_doc_t *doc;
  bool valid;
} proton_app_instance_string_array_validation_t;

typedef struct {
  const proton_json_doc_t *doc;
  bool valid;
  bool has_abi_version;
  bool has_urls;
  bool has_files;
  bool has_reopen;
} proton_app_instance_activation_validation_t;

static proton_app_instance_slot_t
    g_app_instances[PROTON_APP_INSTANCE_CAPACITY];

static void proton_app_instance_set_message(char *error, size_t error_len,
                                            const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static uint64_t proton_app_instance_hash(const char *value) {
  uint64_t hash = UINT64_C(1469598103934665603);
  for (const unsigned char *cursor = (const unsigned char *)value; *cursor;
       cursor++) {
    hash ^= (uint64_t)*cursor;
    hash *= UINT64_C(1099511628211);
  }
  return hash;
}

static int64_t proton_app_instance_make_handle(uint32_t generation,
                                               uint32_t index) {
  uint64_t raw =
      (PROTON_APP_INSTANCE_HANDLE_TYPE
       << PROTON_APP_INSTANCE_HANDLE_TYPE_SHIFT) |
      ((uint64_t)generation
       << PROTON_APP_INSTANCE_HANDLE_GENERATION_SHIFT) |
      (uint64_t)index;
  return (int64_t)raw;
}

static uint32_t proton_app_instance_next_generation(uint32_t generation) {
  generation++;
  return generation == 0 ? 1 : generation;
}

static proton_app_instance_slot_t *
proton_app_instance_get(int64_t handle, char *error, size_t error_len) {
  uint64_t raw = (uint64_t)handle;
  if ((raw >> PROTON_APP_INSTANCE_HANDLE_TYPE_SHIFT) !=
      PROTON_APP_INSTANCE_HANDLE_TYPE) {
    proton_app_instance_set_message(error, error_len,
                                    "invalid app instance handle");
    return NULL;
  }
  uint32_t index =
      (uint32_t)(raw & PROTON_APP_INSTANCE_HANDLE_INDEX_MASK);
  uint32_t generation =
      (uint32_t)((raw >> PROTON_APP_INSTANCE_HANDLE_GENERATION_SHIFT) &
                 0x0fffffffU);
  if (index >= PROTON_APP_INSTANCE_CAPACITY) {
    proton_app_instance_set_message(error, error_len,
                                    "app instance handle is out of range");
    return NULL;
  }
  proton_app_instance_slot_t *slot = &g_app_instances[index];
  if (!slot->occupied || slot->destroyed ||
      slot->generation != generation) {
    proton_app_instance_set_message(error, error_len,
                                    "app instance handle is not active");
    return NULL;
  }
  return slot;
}

static bool proton_app_instance_validate_string_item(
    proton_json_value_t value, void *user_data) {
  proton_app_instance_string_array_validation_t *validation =
      (proton_app_instance_string_array_validation_t *)user_data;
  char *text = proton_json_copy_string(validation->doc, value);
  if (text == NULL) {
    validation->valid = false;
    return false;
  }
  free(text);
  return true;
}

static bool proton_app_instance_validate_activation_field(
    const char *key, proton_json_value_t value, void *user_data) {
  proton_app_instance_activation_validation_t *validation =
      (proton_app_instance_activation_validation_t *)user_data;
  if (strcmp(key, "abi_version") == 0) {
    if (validation->has_abi_version) {
      validation->valid = false;
      return false;
    }
    int32_t abi_version = 0;
    validation->has_abi_version = true;
    validation->valid =
        proton_json_read_int32(validation->doc, value, &abi_version) &&
        abi_version == 1;
    return validation->valid;
  }
  if (strcmp(key, "urls") == 0 || strcmp(key, "files") == 0) {
    bool *seen =
        strcmp(key, "urls") == 0 ? &validation->has_urls
                                 : &validation->has_files;
    if (*seen) {
      validation->valid = false;
      return false;
    }
    *seen = true;
    if (!proton_json_is_array(validation->doc, value)) {
      validation->valid = false;
      return false;
    }
    proton_app_instance_string_array_validation_t items = {
        .doc = validation->doc,
        .valid = true,
    };
    if (!proton_json_array_each(validation->doc, value,
                                proton_app_instance_validate_string_item,
                                &items) ||
        !items.valid) {
      validation->valid = false;
      return false;
    }
    return true;
  }
  if (strcmp(key, "reopen") == 0) {
    if (validation->has_reopen) {
      validation->valid = false;
      return false;
    }
    validation->has_reopen = true;
    bool reopen = false;
    if (!proton_json_read_bool(validation->doc, value, &reopen)) {
      validation->valid = false;
      return false;
    }
    return true;
  }
  validation->valid = false;
  return false;
}

static bool proton_app_instance_validate_activation(
    const char *activation_json) {
  proton_json_doc_t doc;
  if (!proton_json_parse(&doc, activation_json) ||
      !proton_json_is_single_value(&doc)) {
    return false;
  }
  proton_json_value_t root;
  proton_app_instance_activation_validation_t validation = {
      .doc = &doc,
      .valid = true,
      .has_abi_version = false,
      .has_urls = false,
      .has_files = false,
      .has_reopen = false,
  };
  bool valid =
      proton_json_root_object(&doc, &root) &&
      proton_json_object_each(&doc, root,
                              proton_app_instance_validate_activation_field,
                              &validation) &&
      validation.valid && validation.has_abi_version &&
      validation.has_urls && validation.has_files &&
      validation.has_reopen;
  proton_json_dispose(&doc);
  return valid;
}

static void proton_app_instance_lock(proton_app_instance_slot_t *slot) {
#ifdef _WIN32
  EnterCriticalSection(&slot->lock);
#else
  pthread_mutex_lock(&slot->lock);
#endif
}

static void proton_app_instance_unlock(proton_app_instance_slot_t *slot) {
#ifdef _WIN32
  LeaveCriticalSection(&slot->lock);
#else
  pthread_mutex_unlock(&slot->lock);
#endif
}

static bool proton_app_instance_enqueue_owned(
    proton_app_instance_slot_t *slot, proton_event_t *event) {
  if (slot->event_count >= PROTON_APP_INSTANCE_EVENT_CAPACITY) {
    return false;
  }
  uint32_t index =
      (slot->event_head + slot->event_count) %
      PROTON_APP_INSTANCE_EVENT_CAPACITY;
  slot->events[index] = event;
  slot->event_count++;
  return true;
}

typedef struct {
  const proton_json_doc_t *doc;
  char **items;
  int32_t count;
  bool valid;
} proton_app_instance_item_collector_t;

static bool proton_app_instance_collect_item(proton_json_value_t value,
                                             void *user_data) {
  proton_app_instance_item_collector_t *collector =
      (proton_app_instance_item_collector_t *)user_data;
  char *item = proton_json_copy_string(collector->doc, value);
  if (item == NULL) {
    collector->valid = false;
    return false;
  }
  char **items = (char **)realloc(
      collector->items, (size_t)(collector->count + 1) * sizeof(char *));
  if (items == NULL) {
    free(item);
    collector->valid = false;
    return false;
  }
  collector->items = items;
  collector->items[collector->count++] = item;
  return true;
}

static bool proton_app_instance_create_items_event(
    const proton_json_doc_t *doc, proton_json_value_t value,
    proton_event_kind_t kind, proton_event_t **out_event) {
  *out_event = NULL;
  proton_app_instance_item_collector_t collector = {
      .doc = doc,
      .valid = true,
  };
  if (!proton_json_array_each(doc, value, proton_app_instance_collect_item,
                              &collector) ||
      !collector.valid) {
    for (int32_t i = 0; i < collector.count; i++) {
      free(collector.items[i]);
    }
    free(collector.items);
    return false;
  }
  if (collector.count == 0) {
    free(collector.items);
    return true;
  }
  proton_event_t *event = proton_event_create(kind);
  if (event == NULL) {
    for (int32_t i = 0; i < collector.count; i++) {
      free(collector.items[i]);
    }
    free(collector.items);
    return false;
  }
  event->items = collector.items;
  event->item_count = collector.count;
  *out_event = event;
  return true;
}

static bool proton_app_instance_enqueue_activation(
    proton_app_instance_slot_t *slot, const char *activation_json,
    bool reopen_when_empty) {
  proton_json_doc_t doc;
  if (!proton_json_parse(&doc, activation_json) ||
      !proton_json_is_single_value(&doc)) {
    return false;
  }
  proton_json_value_t root;
  bool ok = proton_json_root_object(&doc, &root);
  proton_event_t *events[3] = {NULL, NULL, NULL};
  size_t event_count = 0;
  const char *field_names[] = {"urls", "files"};
  const proton_event_kind_t event_kinds[] = {
      PROTON_EVENT_OPEN_URLS,
      PROTON_EVENT_OPEN_FILES,
  };
  for (size_t i = 0; ok && i < 2; i++) {
    proton_json_value_t value;
    if (!proton_json_object_get(&doc, root, field_names[i], &value)) {
      continue;
    }
    proton_event_t *event = NULL;
    ok = proton_app_instance_create_items_event(
        &doc, value, event_kinds[i], &event);
    if (event != NULL) {
      events[event_count++] = event;
    }
  }
  if (ok) {
    proton_json_value_t reopen_value;
    bool reopen = false;
    if (proton_json_object_get(&doc, root, "reopen", &reopen_value)) {
      ok = proton_json_read_bool(&doc, reopen_value, &reopen);
    }
    if (ok && (reopen || (reopen_when_empty && event_count == 0))) {
      events[event_count] = proton_event_create(PROTON_EVENT_REOPEN);
      ok = events[event_count] != NULL;
      if (ok) {
        event_count++;
      }
    }
  }
  proton_json_dispose(&doc);
  if (!ok) {
    for (size_t i = 0; i < event_count; i++) {
      proton_event_destroy(events[i]);
    }
    return false;
  }

  proton_app_instance_lock(slot);
  bool attached = slot->runtime != NULL;
  if (!attached &&
      event_count > PROTON_APP_INSTANCE_EVENT_CAPACITY - slot->event_count) {
    ok = false;
  } else if (!attached) {
    for (size_t i = 0; i < event_count; i++) {
      (void)proton_app_instance_enqueue_owned(slot, events[i]);
      events[i] = NULL;
    }
  }
  proton_app_instance_unlock(slot);
  if (ok && attached) {
    for (size_t i = 0; i < event_count; i++) {
      if (!proton_event_publish(events[i])) {
        ok = false;
      }
      events[i] = NULL;
    }
  }
  for (size_t i = 0; i < event_count; i++) {
    proton_event_destroy(events[i]);
  }
  return ok;
}

static proton_app_instance_slot_t *proton_app_instance_allocate(
    uint32_t *out_index, char *error, size_t error_len) {
  for (uint32_t i = 0; i < PROTON_APP_INSTANCE_CAPACITY; i++) {
    proton_app_instance_slot_t *slot = &g_app_instances[i];
    if (slot->occupied && !slot->destroyed) {
      continue;
    }
    uint32_t generation =
        slot->generation == 0
            ? 1
            : proton_app_instance_next_generation(slot->generation);
    memset(slot, 0, sizeof(*slot));
    slot->generation = generation;
    slot->occupied = true;
    slot->destroyed = false;
#ifdef _WIN32
    InitializeCriticalSection(&slot->lock);
    slot->lock_initialized = true;
#else
    if (pthread_mutex_init(&slot->lock, NULL) != 0) {
      memset(slot, 0, sizeof(*slot));
      proton_app_instance_set_message(error, error_len,
                                      "failed to initialize instance lock");
      return NULL;
    }
    slot->lock_initialized = true;
    slot->ownership_fd = -1;
    slot->listen_fd = -1;
    slot->client_fd = -1;
    atomic_init(&slot->stopping, false);
#endif
    *out_index = i;
    return slot;
  }
  proton_app_instance_set_message(error, error_len,
                                  "app instance registry is full");
  return NULL;
}

static void proton_app_instance_clear_events(
    proton_app_instance_slot_t *slot) {
  for (uint32_t i = 0; i < PROTON_APP_INSTANCE_EVENT_CAPACITY; i++) {
    proton_event_destroy(slot->events[i]);
    slot->events[i] = NULL;
  }
  slot->event_head = 0;
  slot->event_count = 0;
}

#ifdef _WIN32

static bool proton_app_instance_create_security_descriptor(
    proton_app_instance_slot_t *slot, char *error, size_t error_len) {
  HANDLE token = NULL;
  DWORD required = 0;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    proton_app_instance_set_message(
        error, error_len, "failed to open the current process token");
    return false;
  }
  (void)GetTokenInformation(token, TokenUser, NULL, 0, &required);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || required == 0) {
    CloseHandle(token);
    proton_app_instance_set_message(
        error, error_len, "failed to size the current user identity");
    return false;
  }
  TOKEN_USER *user = (TOKEN_USER *)malloc(required);
  if (user == NULL ||
      !GetTokenInformation(token, TokenUser, user, required, &required)) {
    free(user);
    CloseHandle(token);
    proton_app_instance_set_message(
        error, error_len, "failed to read the current user identity");
    return false;
  }
  LPWSTR sid = NULL;
  bool ok = ConvertSidToStringSidW(user->User.Sid, &sid) != 0;
  free(user);
  CloseHandle(token);
  if (!ok) {
    proton_app_instance_set_message(
        error, error_len, "failed to encode the current user identity");
    return false;
  }
  size_t descriptor_length = wcslen(sid) + 64;
  wchar_t *descriptor = (wchar_t *)malloc(
      descriptor_length * sizeof(wchar_t));
  if (descriptor == NULL) {
    LocalFree(sid);
    proton_app_instance_set_message(
        error, error_len, "failed to allocate instance security policy");
    return false;
  }
  _snwprintf_s(descriptor, descriptor_length, _TRUNCATE,
               L"D:P(A;;GA;;;SY)(A;;GA;;;%ls)", sid);
  LocalFree(sid);
  ok = ConvertStringSecurityDescriptorToSecurityDescriptorW(
           descriptor, SDDL_REVISION_1, &slot->security_descriptor, NULL) != 0;
  free(descriptor);
  if (!ok) {
    proton_app_instance_set_message(
        error, error_len, "failed to create instance security policy");
  }
  return ok;
}

static bool proton_app_instance_read_exact(HANDLE pipe, void *buffer,
                                           DWORD length) {
  unsigned char *cursor = (unsigned char *)buffer;
  while (length > 0) {
    DWORD read = 0;
    if (!ReadFile(pipe, cursor, length, &read, NULL) || read == 0) {
      return false;
    }
    cursor += read;
    length -= read;
  }
  return true;
}

static bool proton_app_instance_write_exact(HANDLE pipe, const void *buffer,
                                            DWORD length) {
  const unsigned char *cursor = (const unsigned char *)buffer;
  while (length > 0) {
    DWORD written = 0;
    if (!WriteFile(pipe, cursor, length, &written, NULL) || written == 0) {
      return false;
    }
    cursor += written;
    length -= written;
  }
  return true;
}

typedef enum proton_app_instance_io_result {
  PROTON_APP_INSTANCE_IO_COMPLETE = 0,
  PROTON_APP_INSTANCE_IO_STOPPED = 1,
  PROTON_APP_INSTANCE_IO_FAILED = 2,
} proton_app_instance_io_result_t;

// Server operations must remain cancellable so instance destruction can always
// join the listener thread, regardless of which pipe operation is pending.
static proton_app_instance_io_result_t proton_app_instance_wait_for_server_io(
    proton_app_instance_slot_t *slot, HANDLE pipe, OVERLAPPED *operation,
    DWORD *transferred) {
  HANDLE events[2] = {slot->stop_event, operation->hEvent};
  DWORD wait_result = WaitForMultipleObjects(2, events, FALSE, INFINITE);
  if (wait_result == WAIT_OBJECT_0 + 1) {
    return GetOverlappedResult(pipe, operation, transferred, FALSE)
               ? PROTON_APP_INSTANCE_IO_COMPLETE
               : PROTON_APP_INSTANCE_IO_FAILED;
  }

  (void)CancelIoEx(pipe, operation);
  DWORD ignored = 0;
  (void)GetOverlappedResult(pipe, operation, &ignored, TRUE);
  return wait_result == WAIT_OBJECT_0 ? PROTON_APP_INSTANCE_IO_STOPPED
                                     : PROTON_APP_INSTANCE_IO_FAILED;
}

static proton_app_instance_io_result_t proton_app_instance_server_connect(
    proton_app_instance_slot_t *slot, HANDLE pipe) {
  if (WaitForSingleObject(slot->stop_event, 0) == WAIT_OBJECT_0) {
    return PROTON_APP_INSTANCE_IO_STOPPED;
  }
  HANDLE event = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (event == NULL) {
    return PROTON_APP_INSTANCE_IO_FAILED;
  }
  OVERLAPPED operation = {0};
  operation.hEvent = event;
  BOOL connected = ConnectNamedPipe(pipe, &operation);
  proton_app_instance_io_result_t result = PROTON_APP_INSTANCE_IO_COMPLETE;
  if (!connected) {
    DWORD connect_error = GetLastError();
    if (connect_error == ERROR_IO_PENDING) {
      DWORD ignored = 0;
      result = proton_app_instance_wait_for_server_io(
          slot, pipe, &operation, &ignored);
    } else if (connect_error != ERROR_PIPE_CONNECTED) {
      result = PROTON_APP_INSTANCE_IO_FAILED;
    }
  }
  CloseHandle(event);
  return result;
}

static proton_app_instance_io_result_t proton_app_instance_server_io_exact(
    proton_app_instance_slot_t *slot, HANDLE pipe, void *buffer, DWORD length,
    bool write) {
  unsigned char *cursor = (unsigned char *)buffer;
  while (length > 0) {
    if (WaitForSingleObject(slot->stop_event, 0) == WAIT_OBJECT_0) {
      return PROTON_APP_INSTANCE_IO_STOPPED;
    }
    HANDLE event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (event == NULL) {
      return PROTON_APP_INSTANCE_IO_FAILED;
    }
    OVERLAPPED operation = {0};
    operation.hEvent = event;
    BOOL completed = write
                         ? WriteFile(pipe, cursor, length, NULL, &operation)
                         : ReadFile(pipe, cursor, length, NULL, &operation);
    DWORD transferred = 0;
    proton_app_instance_io_result_t result = PROTON_APP_INSTANCE_IO_COMPLETE;
    if (completed) {
      if (!GetOverlappedResult(pipe, &operation, &transferred, FALSE)) {
        result = PROTON_APP_INSTANCE_IO_FAILED;
      }
    } else if (GetLastError() == ERROR_IO_PENDING) {
      result = proton_app_instance_wait_for_server_io(
          slot, pipe, &operation, &transferred);
    } else {
      result = PROTON_APP_INSTANCE_IO_FAILED;
    }
    CloseHandle(event);
    if (result != PROTON_APP_INSTANCE_IO_COMPLETE) {
      return result;
    }
    if (transferred == 0) {
      return PROTON_APP_INSTANCE_IO_FAILED;
    }
    cursor += transferred;
    length -= transferred;
  }
  return PROTON_APP_INSTANCE_IO_COMPLETE;
}

static DWORD WINAPI proton_app_instance_server_thread(void *data) {
  proton_app_instance_slot_t *slot = (proton_app_instance_slot_t *)data;
  SECURITY_ATTRIBUTES security = {
      .nLength = sizeof(SECURITY_ATTRIBUTES),
      .lpSecurityDescriptor = slot->security_descriptor,
      .bInheritHandle = FALSE,
  };
  for (;;) {
    if (WaitForSingleObject(slot->stop_event, 0) == WAIT_OBJECT_0) {
      return 0;
    }
    HANDLE pipe = CreateNamedPipeW(
        slot->pipe_name, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
            PIPE_REJECT_REMOTE_CLIENTS,
        1, 16, PROTON_APP_INSTANCE_MAX_MESSAGE_BYTES, 0, &security);
    if (pipe == INVALID_HANDLE_VALUE) {
      return 1;
    }
    proton_app_instance_io_result_t connect_result =
        proton_app_instance_server_connect(slot, pipe);
    if (connect_result != PROTON_APP_INSTANCE_IO_COMPLETE) {
      CloseHandle(pipe);
      if (connect_result == PROTON_APP_INSTANCE_IO_STOPPED) {
        return 0;
      }
      continue;
    }
    uint32_t length = 0;
    unsigned char ack = 0;
    proton_app_instance_io_result_t read_result =
        proton_app_instance_server_io_exact(
            slot, pipe, &length, sizeof(length), false);
    if (read_result == PROTON_APP_INSTANCE_IO_COMPLETE &&
        length > 0 && length < PROTON_APP_INSTANCE_MAX_MESSAGE_BYTES) {
      char *payload = (char *)malloc((size_t)length + 1);
      if (payload != NULL) {
        read_result = proton_app_instance_server_io_exact(
            slot, pipe, payload, length, false);
      }
      if (payload != NULL &&
          read_result == PROTON_APP_INSTANCE_IO_COMPLETE) {
        payload[length] = '\0';
        if (proton_app_instance_validate_activation(payload) &&
            proton_app_instance_enqueue_activation(slot, payload, true)) {
          ack = 1;
        }
      }
      free(payload);
    }
    if (read_result == PROTON_APP_INSTANCE_IO_STOPPED) {
      CloseHandle(pipe);
      return 0;
    }
    proton_app_instance_io_result_t write_result =
        proton_app_instance_server_io_exact(
            slot, pipe, &ack, sizeof(ack), true);
    if (write_result == PROTON_APP_INSTANCE_IO_STOPPED) {
      CloseHandle(pipe);
      return 0;
    }
    if (write_result == PROTON_APP_INSTANCE_IO_COMPLETE && ack == 1) {
      unsigned char receipt = 0;
      proton_app_instance_io_result_t receipt_result =
          proton_app_instance_server_io_exact(
              slot, pipe, &receipt, sizeof(receipt), false);
      if (receipt_result == PROTON_APP_INSTANCE_IO_STOPPED) {
        CloseHandle(pipe);
        return 0;
      }
    }
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
}

static int32_t proton_app_instance_forward_windows(
    const wchar_t *pipe_name, const char *activation_json, char *error,
    size_t error_len) {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  for (int attempt = 0; attempt < 500; attempt++) {
    pipe = CreateFileW(pipe_name, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                       OPEN_EXISTING, 0, NULL);
    if (pipe != INVALID_HANDLE_VALUE) {
      break;
    }
    DWORD connect_error = GetLastError();
    if (connect_error == ERROR_PIPE_BUSY) {
      (void)WaitNamedPipeW(pipe_name, 10);
    } else if (connect_error == ERROR_FILE_NOT_FOUND) {
      Sleep(10);
    } else {
      break;
    }
  }
  if (pipe == INVALID_HANDLE_VALUE) {
    proton_app_instance_set_message(error, error_len,
                                    "primary instance did not open its pipe");
    return PROTON_ERR_PLATFORM;
  }
  ULONG primary_process_id = 0;
  if (GetNamedPipeServerProcessId(pipe, &primary_process_id)) {
    (void)AllowSetForegroundWindow((DWORD)primary_process_id);
  }
  size_t length = strlen(activation_json);
  uint32_t wire_length = (uint32_t)length;
  unsigned char ack = 0;
  bool ok =
      proton_app_instance_write_exact(pipe, &wire_length, sizeof(wire_length)) &&
      proton_app_instance_write_exact(pipe, activation_json, wire_length) &&
      proton_app_instance_read_exact(pipe, &ack, sizeof(ack)) && ack == 1;
  if (ok) {
    unsigned char receipt = 1;
    (void)proton_app_instance_write_exact(pipe, &receipt, sizeof(receipt));
  }
  CloseHandle(pipe);
  if (!ok) {
    proton_app_instance_set_message(error, error_len,
                                    "primary instance rejected activation");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

static int32_t proton_app_instance_acquire_platform(
    proton_app_instance_slot_t *slot, const char *identifier,
    const char *activation_json, bool *out_primary, char *error,
    size_t error_len) {
  uint64_t hash = proton_app_instance_hash(identifier);
  DWORD session_id = 0;
  if (!ProcessIdToSessionId(GetCurrentProcessId(), &session_id)) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to identify the login session");
    return PROTON_ERR_PLATFORM;
  }
  wchar_t mutex_name[128];
  _snwprintf_s(mutex_name, 128, _TRUNCATE,
               L"Local\\Proton.AppInstance.%08lx.%016llx",
               (unsigned long)session_id,
               (unsigned long long)hash);
  _snwprintf_s(slot->pipe_name, 128, _TRUNCATE,
               L"\\\\.\\pipe\\Proton.AppInstance.%08lx.%016llx",
               (unsigned long)session_id,
               (unsigned long long)hash);
  if (!proton_app_instance_create_security_descriptor(
          slot, error, error_len)) {
    return PROTON_ERR_PLATFORM;
  }
  SECURITY_ATTRIBUTES security = {
      .nLength = sizeof(SECURITY_ATTRIBUTES),
      .lpSecurityDescriptor = slot->security_descriptor,
      .bInheritHandle = FALSE,
  };
  slot->mutex = CreateMutexW(&security, FALSE, mutex_name);
  if (slot->mutex == NULL) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to create instance mutex");
    return PROTON_ERR_PLATFORM;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(slot->mutex);
    slot->mutex = NULL;
    *out_primary = false;
    return proton_app_instance_forward_windows(
        slot->pipe_name, activation_json, error, error_len);
  }
  slot->owns_endpoint = true;
  slot->stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (slot->stop_event == NULL) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to create instance stop event");
    return PROTON_ERR_PLATFORM;
  }
  slot->thread = CreateThread(NULL, 0, proton_app_instance_server_thread, slot,
                              0, NULL);
  if (slot->thread == NULL) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to start instance listener");
    return PROTON_ERR_PLATFORM;
  }
  *out_primary = true;
  return PROTON_OK;
}

static void proton_app_instance_stop_platform(
    proton_app_instance_slot_t *slot) {
  if (slot->owns_endpoint && slot->stop_event != NULL) {
    SetEvent(slot->stop_event);
  }
  if (slot->owns_endpoint && slot->thread != NULL) {
    WaitForSingleObject(slot->thread, INFINITE);
    CloseHandle(slot->thread);
    slot->thread = NULL;
  }
  if (slot->stop_event != NULL) {
    CloseHandle(slot->stop_event);
    slot->stop_event = NULL;
  }
  if (slot->mutex != NULL) {
    CloseHandle(slot->mutex);
    slot->mutex = NULL;
  }
  if (slot->security_descriptor != NULL) {
    LocalFree(slot->security_descriptor);
    slot->security_descriptor = NULL;
  }
  slot->owns_endpoint = false;
}

#else

static bool proton_app_instance_read_exact(int fd, void *buffer,
                                           size_t length) {
  unsigned char *cursor = (unsigned char *)buffer;
  while (length > 0) {
    ssize_t read_count = recv(fd, cursor, length, 0);
    if (read_count <= 0) {
      return false;
    }
    cursor += (size_t)read_count;
    length -= (size_t)read_count;
  }
  return true;
}

static bool proton_app_instance_write_exact(int fd, const void *buffer,
                                            size_t length) {
  const unsigned char *cursor = (const unsigned char *)buffer;
  while (length > 0) {
#ifdef MSG_NOSIGNAL
    ssize_t written = send(fd, cursor, length, MSG_NOSIGNAL);
#else
    ssize_t written = send(fd, cursor, length, 0);
#endif
    if (written <= 0) {
      return false;
    }
    cursor += (size_t)written;
    length -= (size_t)written;
  }
  return true;
}

static bool proton_app_instance_peer_is_current_user(int fd) {
#if defined(__linux__)
  struct ucred credentials;
  socklen_t length = sizeof(credentials);
  return getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &credentials, &length) == 0 &&
         credentials.uid == geteuid();
#elif defined(__APPLE__)
  uid_t uid = 0;
  gid_t gid = 0;
  return getpeereid(fd, &uid, &gid) == 0 && uid == geteuid();
#else
  (void)fd;
  return true;
#endif
}

static void *proton_app_instance_server_thread(void *data) {
  proton_app_instance_slot_t *slot = (proton_app_instance_slot_t *)data;
  while (!atomic_load_explicit(&slot->stopping, memory_order_acquire)) {
    int client = accept(slot->listen_fd, NULL, NULL);
    if (client < 0) {
      if (atomic_load_explicit(&slot->stopping, memory_order_acquire)) {
        break;
      }
      continue;
    }
    proton_app_instance_lock(slot);
    if (atomic_load_explicit(&slot->stopping, memory_order_acquire)) {
      proton_app_instance_unlock(slot);
      close(client);
      break;
    }
    slot->client_fd = client;
    proton_app_instance_unlock(slot);
#ifdef SO_NOSIGPIPE
    int enabled = 1;
    (void)setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
                     sizeof(enabled));
#endif
    uint32_t wire_length = 0;
    unsigned char ack = 0;
    if (proton_app_instance_peer_is_current_user(client) &&
        proton_app_instance_read_exact(client, &wire_length,
                                       sizeof(wire_length))) {
      uint32_t length = ntohl(wire_length);
      if (length > 0 && length < PROTON_APP_INSTANCE_MAX_MESSAGE_BYTES) {
        char *payload = (char *)malloc((size_t)length + 1);
        if (payload != NULL &&
            proton_app_instance_read_exact(client, payload, length)) {
          payload[length] = '\0';
          if (proton_app_instance_validate_activation(payload) &&
              proton_app_instance_enqueue_activation(slot, payload, true)) {
            ack = 1;
          }
        }
        free(payload);
      }
    }
    (void)proton_app_instance_write_exact(client, &ack, sizeof(ack));
    proton_app_instance_lock(slot);
    if (slot->client_fd == client) {
      slot->client_fd = -1;
    }
    proton_app_instance_unlock(slot);
    close(client);
  }
  return NULL;
}

static int proton_app_instance_connect(const char *socket_path) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }
#ifdef SO_NOSIGPIPE
  int enabled = 1;
  (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled));
#endif
  struct sockaddr_un address;
  memset(&address, 0, sizeof(address));
  address.sun_family = AF_UNIX;
  snprintf(address.sun_path, sizeof(address.sun_path), "%s", socket_path);
  if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
    int connect_error = errno;
    close(fd);
    errno = connect_error;
    return -1;
  }
  return fd;
}

static int proton_app_instance_connect_with_retry(
    const char *socket_path) {
  const struct timespec retry_delay = {
      .tv_sec = 0,
      .tv_nsec = 10 * 1000 * 1000,
  };
  for (int attempt = 0; attempt < 500; attempt++) {
    int fd = proton_app_instance_connect(socket_path);
    if (fd >= 0) {
      return fd;
    }
    if (errno != ENOENT && errno != ECONNREFUSED) {
      return -1;
    }
    nanosleep(&retry_delay, NULL);
  }
  return -1;
}

static int32_t proton_app_instance_forward_posix(
    const char *socket_path, const char *activation_json, char *error,
    size_t error_len) {
  int fd = proton_app_instance_connect_with_retry(socket_path);
  if (fd < 0) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to connect to primary instance");
    return PROTON_ERR_PLATFORM;
  }
  size_t length = strlen(activation_json);
  uint32_t wire_length = htonl((uint32_t)length);
  unsigned char ack = 0;
  bool ok =
      proton_app_instance_write_exact(fd, &wire_length, sizeof(wire_length)) &&
      proton_app_instance_write_exact(fd, activation_json, length) &&
      proton_app_instance_read_exact(fd, &ack, sizeof(ack)) && ack == 1;
  close(fd);
  if (!ok) {
    proton_app_instance_set_message(error, error_len,
                                    "primary instance rejected activation");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

static bool proton_app_instance_remove_owned_socket(
    const char *socket_path) {
  struct stat info;
  if (lstat(socket_path, &info) != 0) {
    return errno == ENOENT;
  }
  return S_ISSOCK(info.st_mode) && info.st_uid == geteuid() &&
         unlink(socket_path) == 0;
}

static bool proton_app_instance_prepare_directory(
    char *directory, size_t directory_len, char *error,
    size_t error_len) {
  int written = snprintf(directory, directory_len, "/tmp/proton-%lu",
                         (unsigned long)geteuid());
  if (written < 0 || (size_t)written >= directory_len) {
    proton_app_instance_set_message(error, error_len,
                                    "instance directory path is too long");
    return false;
  }
  if (mkdir(directory, S_IRWXU) != 0 && errno != EEXIST) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to create instance directory");
    return false;
  }
  struct stat info;
  if (lstat(directory, &info) != 0 || !S_ISDIR(info.st_mode) ||
      info.st_uid != geteuid() ||
      (info.st_mode & (S_IRWXG | S_IRWXO)) != 0) {
    proton_app_instance_set_message(
        error, error_len, "instance directory is not private to the current user");
    return false;
  }
  return true;
}

static int32_t proton_app_instance_acquire_platform(
    proton_app_instance_slot_t *slot, const char *identifier,
    const char *activation_json, bool *out_primary, char *error,
    size_t error_len) {
  uint64_t hash = proton_app_instance_hash(identifier);
  char directory[64];
  if (!proton_app_instance_prepare_directory(
          directory, sizeof(directory), error, error_len)) {
    return PROTON_ERR_PLATFORM;
  }
  snprintf(slot->ownership_path, sizeof(slot->ownership_path),
           "%s/%016llx.lock", directory, (unsigned long long)hash);
  snprintf(slot->socket_path, sizeof(slot->socket_path),
           "%s/%016llx.sock", directory, (unsigned long long)hash);
  int ownership_flags = O_CREAT | O_RDWR;
#ifdef O_CLOEXEC
  ownership_flags |= O_CLOEXEC;
#endif
#ifdef O_NOFOLLOW
  ownership_flags |= O_NOFOLLOW;
#endif
  slot->ownership_fd =
      open(slot->ownership_path, ownership_flags, S_IRUSR | S_IWUSR);
  if (slot->ownership_fd < 0) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to open instance ownership lock");
    return PROTON_ERR_PLATFORM;
  }
  struct stat ownership_info;
  if (fstat(slot->ownership_fd, &ownership_info) != 0 ||
      !S_ISREG(ownership_info.st_mode) ||
      ownership_info.st_uid != geteuid() ||
      (ownership_info.st_mode & (S_IRWXG | S_IRWXO)) != 0) {
    proton_app_instance_set_message(
        error, error_len, "instance ownership lock has an invalid owner");
    return PROTON_ERR_PLATFORM;
  }
  if (flock(slot->ownership_fd, LOCK_EX | LOCK_NB) != 0) {
    if (errno != EWOULDBLOCK && errno != EAGAIN) {
      proton_app_instance_set_message(
          error, error_len, "failed to acquire instance ownership lock");
      return PROTON_ERR_PLATFORM;
    }
    *out_primary = false;
    return proton_app_instance_forward_posix(
        slot->socket_path, activation_json, error, error_len);
  }
  slot->owns_endpoint = true;
  if (!proton_app_instance_remove_owned_socket(slot->socket_path)) {
    proton_app_instance_set_message(
        error, error_len, "failed to remove stale instance socket");
    return PROTON_ERR_PLATFORM;
  }
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    proton_app_instance_set_message(error, error_len,
                                    "failed to create instance socket");
    return PROTON_ERR_PLATFORM;
  }
  struct sockaddr_un address;
  memset(&address, 0, sizeof(address));
  address.sun_family = AF_UNIX;
  snprintf(address.sun_path, sizeof(address.sun_path), "%s",
           slot->socket_path);
  if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
    close(fd);
    proton_app_instance_set_message(error, error_len,
                                    "failed to bind instance socket");
    return PROTON_ERR_PLATFORM;
  }
  if (chmod(slot->socket_path, S_IRUSR | S_IWUSR) != 0 ||
      listen(fd, 8) != 0) {
    close(fd);
    unlink(slot->socket_path);
    proton_app_instance_set_message(error, error_len,
                                    "failed to listen for app activations");
    return PROTON_ERR_PLATFORM;
  }
  slot->listen_fd = fd;
  if (pthread_create(&slot->thread, NULL,
                     proton_app_instance_server_thread, slot) != 0) {
    close(fd);
    slot->listen_fd = -1;
    unlink(slot->socket_path);
    proton_app_instance_set_message(error, error_len,
                                    "failed to start instance listener");
    return PROTON_ERR_PLATFORM;
  }
  slot->thread_started = true;
  slot->owns_endpoint = true;
  *out_primary = true;
  return PROTON_OK;
}

static void proton_app_instance_stop_platform(
    proton_app_instance_slot_t *slot) {
  if (slot->owns_endpoint) {
    atomic_store_explicit(&slot->stopping, true, memory_order_release);
  }
  if (slot->owns_endpoint && slot->listen_fd >= 0) {
    shutdown(slot->listen_fd, SHUT_RDWR);
    close(slot->listen_fd);
    slot->listen_fd = -1;
  }
  proton_app_instance_lock(slot);
  if (slot->client_fd >= 0) {
    shutdown(slot->client_fd, SHUT_RDWR);
  }
  proton_app_instance_unlock(slot);
  if (slot->owns_endpoint && slot->thread_started) {
    pthread_join(slot->thread, NULL);
    slot->thread_started = false;
  }
  if (slot->owns_endpoint && slot->socket_path[0] != '\0') {
    unlink(slot->socket_path);
  }
  if (slot->ownership_fd >= 0) {
    (void)flock(slot->ownership_fd, LOCK_UN);
    close(slot->ownership_fd);
    slot->ownership_fd = -1;
  }
  slot->owns_endpoint = false;
}

#endif

static void proton_app_instance_dispose_slot(
    proton_app_instance_slot_t *slot) {
  proton_app_instance_stop_platform(slot);
  proton_app_instance_lock(slot);
  slot->runtime = NULL;
  proton_app_instance_clear_events(slot);
  proton_app_instance_unlock(slot);
#ifdef _WIN32
  if (slot->lock_initialized) {
    DeleteCriticalSection(&slot->lock);
    slot->lock_initialized = false;
  }
#else
  if (slot->lock_initialized) {
    pthread_mutex_destroy(&slot->lock);
    slot->lock_initialized = false;
  }
#endif
  slot->destroyed = true;
  slot->occupied = false;
}

int32_t proton_app_instance_acquire_impl(
    const char *identifier, const char *activation_json,
    int64_t *out_instance, int32_t *out_primary, char *error,
    size_t error_len) {
  if (out_instance == NULL || out_primary == NULL) {
    proton_app_instance_set_message(
        error, error_len, "out_instance and out_primary are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_instance = PROTON_INVALID_HANDLE;
  *out_primary = 0;
  if (identifier == NULL || identifier[0] == '\0' ||
      strlen(identifier) > 255) {
    proton_app_instance_set_message(
        error, error_len, "app identifier must contain 1 to 255 bytes");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (activation_json == NULL ||
      strlen(activation_json) >= PROTON_APP_INSTANCE_MAX_MESSAGE_BYTES ||
      !proton_app_instance_validate_activation(activation_json)) {
    proton_app_instance_set_message(error, error_len,
                                    "invalid app activation JSON");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  uint32_t index = 0;
  proton_app_instance_slot_t *slot =
      proton_app_instance_allocate(&index, error, error_len);
  if (slot == NULL) {
    return PROTON_ERR_ENGINE;
  }
  bool primary = false;
  int32_t status = proton_app_instance_acquire_platform(
      slot, identifier, activation_json, &primary, error, error_len);
  if (status != PROTON_OK) {
    proton_app_instance_dispose_slot(slot);
    return status;
  }
  if (!primary) {
    proton_app_instance_dispose_slot(slot);
    *out_primary = 0;
    return PROTON_OK;
  }
  if (!proton_app_instance_enqueue_activation(slot, activation_json, false)) {
    proton_app_instance_dispose_slot(slot);
    proton_app_instance_set_message(error, error_len,
                                    "failed to queue initial activation");
    return PROTON_ERR_QUEUE_FAILED;
  }
  *out_instance = proton_app_instance_make_handle(slot->generation, index);
  *out_primary = 1;
  return PROTON_OK;
}

int32_t proton_app_instance_attach_runtime_impl(
    int64_t instance, proton_engine_runtime_t *runtime, char *error,
    size_t error_len) {
  if (runtime == NULL) {
    proton_app_instance_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_app_instance_slot_t *slot =
      proton_app_instance_get(instance, error, error_len);
  if (slot == NULL) {
    return PROTON_ERR_INVALID_HANDLE;
  }
  proton_app_instance_lock(slot);
  if (slot->runtime != NULL && slot->runtime != runtime) {
    proton_app_instance_unlock(slot);
    proton_app_instance_set_message(
        error, error_len, "app instance is already attached to a runtime");
    return PROTON_ERR_ALREADY_INITIALIZED;
  }
  slot->runtime = runtime;
  while (slot->event_count > 0) {
    proton_event_t *event = slot->events[slot->event_head];
    slot->events[slot->event_head] = NULL;
    slot->event_head =
        (slot->event_head + 1) % PROTON_APP_INSTANCE_EVENT_CAPACITY;
    slot->event_count--;
    if (!proton_event_publish(event)) {
      slot->runtime = NULL;
      proton_app_instance_unlock(slot);
      proton_app_instance_set_message(
          error, error_len, "failed to publish queued app activation");
      return PROTON_ERR_QUEUE_FAILED;
    }
  }
  proton_app_instance_unlock(slot);
  return PROTON_OK;
}

void proton_app_instance_detach_runtime_impl(int64_t instance) {
  char ignored[1];
  proton_app_instance_slot_t *slot =
      proton_app_instance_get(instance, ignored, sizeof(ignored));
  if (slot == NULL) {
    return;
  }
  proton_app_instance_lock(slot);
  slot->runtime = NULL;
  proton_app_instance_unlock(slot);
}

int32_t proton_app_instance_destroy_impl(int64_t instance, char *error,
                                         size_t error_len) {
  proton_app_instance_slot_t *slot =
      proton_app_instance_get(instance, error, error_len);
  if (slot == NULL) {
    return PROTON_ERR_INVALID_HANDLE;
  }
  proton_app_instance_lock(slot);
  bool attached = slot->runtime != NULL;
  proton_app_instance_unlock(slot);
  if (attached) {
    proton_app_instance_set_message(
        error, error_len,
        "app instance must be detached from its runtime before destroy");
    return PROTON_ERR_ALREADY_INITIALIZED;
  }
  proton_app_instance_dispose_slot(slot);
  return PROTON_OK;
}
