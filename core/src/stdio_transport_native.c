#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

struct lepus_core_stdio_transport {
  int closed;
  char *buffer;
  size_t buffer_len;
  size_t buffer_cap;
#ifdef _WIN32
  HANDLE process;
  HANDLE stdin_write;
  HANDLE stdout_read;
#else
  pid_t pid;
  int stdin_write;
  int stdout_read;
#endif
};

static moonbit_bytes_t lepus_core_cstr_bytes(const char *value) {
  size_t len;
  moonbit_bytes_t bytes;
  if (value == NULL) {
    value = "";
  }
  len = strlen(value) + 1;
  bytes = moonbit_make_bytes_raw((int32_t)len);
  memcpy(bytes, value, len);
  return bytes;
}

static void lepus_core_stdio_transport_finalize(void *raw_transport);

static int lepus_core_stdio_transport_reserve(
    struct lepus_core_stdio_transport *transport,
    size_t extra) {
  size_t needed;
  size_t next_cap;
  char *next;
  if (transport == NULL) {
    return 0;
  }
  needed = transport->buffer_len + extra;
  if (needed <= transport->buffer_cap) {
    return 1;
  }
  next_cap = transport->buffer_cap == 0 ? 4096 : transport->buffer_cap;
  while (next_cap < needed) {
    next_cap *= 2;
  }
  next = (char *)realloc(transport->buffer, next_cap);
  if (next == NULL) {
    return 0;
  }
  transport->buffer = next;
  transport->buffer_cap = next_cap;
  return 1;
}

static moonbit_bytes_t lepus_core_stdio_transport_take_line(
    struct lepus_core_stdio_transport *transport) {
  size_t i;
  size_t line_len;
  moonbit_bytes_t bytes;
  if (transport == NULL || transport->buffer_len == 0) {
    return lepus_core_cstr_bytes("");
  }
  for (i = 0; i < transport->buffer_len; i++) {
    if (transport->buffer[i] == '\n') {
      line_len = i;
      bytes = moonbit_make_bytes_raw((int32_t)(line_len + 1));
      memcpy(bytes, transport->buffer, line_len);
      bytes[line_len] = '\0';
      memmove(
          transport->buffer,
          transport->buffer + i + 1,
          transport->buffer_len - i - 1);
      transport->buffer_len -= i + 1;
      return bytes;
    }
  }
  return lepus_core_cstr_bytes("");
}

#ifdef _WIN32
static char *lepus_core_strdup(const char *value) {
  size_t len;
  char *copy;
  if (value == NULL) {
    value = "";
  }
  len = strlen(value) + 1;
  copy = (char *)malloc(len);
  if (copy != NULL) {
    memcpy(copy, value, len);
  }
  return copy;
}
#endif

void *lepus_core_stdio_transport_new(
    moonbit_bytes_t command_line,
    moonbit_bytes_t cwd) {
  struct lepus_core_stdio_transport *transport =
      (struct lepus_core_stdio_transport *)moonbit_make_external_object(
          lepus_core_stdio_transport_finalize, sizeof(*transport));
  if (transport == NULL) {
    return NULL;
  }
  memset(transport, 0, sizeof(*transport));
#ifndef _WIN32
  transport->stdin_write = -1;
  transport->stdout_read = -1;
  transport->pid = -1;
#endif
#ifdef _WIN32
  {
    SECURITY_ATTRIBUTES sa;
    HANDLE child_stdin_read = NULL;
    HANDLE child_stdout_write = NULL;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    char *mutable_command = NULL;
    const char *cwd_value = (const char *)cwd;

    memset(&sa, 0, sizeof(sa));
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    memset(&si, 0, sizeof(si));
    memset(&pi, 0, sizeof(pi));

    if (!CreatePipe(&child_stdin_read, &transport->stdin_write, &sa, 0)) {
      transport->closed = 1;
      return transport;
    }
    if (!SetHandleInformation(transport->stdin_write, HANDLE_FLAG_INHERIT, 0)) {
      transport->closed = 1;
      return transport;
    }
    if (!CreatePipe(&transport->stdout_read, &child_stdout_write, &sa, 0)) {
      transport->closed = 1;
      return transport;
    }
    if (!SetHandleInformation(transport->stdout_read, HANDLE_FLAG_INHERIT, 0)) {
      transport->closed = 1;
      return transport;
    }

    mutable_command = lepus_core_strdup((const char *)command_line);
    if (mutable_command == NULL) {
      transport->closed = 1;
      return transport;
    }

    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = child_stdin_read;
    si.hStdOutput = child_stdout_write;
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

    if (!CreateProcessA(
            NULL,
            mutable_command,
            NULL,
            NULL,
            TRUE,
            CREATE_NO_WINDOW,
            NULL,
            cwd_value != NULL && cwd_value[0] != '\0' ? cwd_value : NULL,
            &si,
            &pi)) {
      transport->closed = 1;
    } else {
      transport->process = pi.hProcess;
      CloseHandle(pi.hThread);
    }
    free(mutable_command);
    CloseHandle(child_stdin_read);
    CloseHandle(child_stdout_write);
  }
#else
  {
    int stdin_pipe[2];
    int stdout_pipe[2];
    if (pipe(stdin_pipe) != 0 || pipe(stdout_pipe) != 0) {
      transport->closed = 1;
      return transport;
    }
    transport->pid = fork();
    if (transport->pid == 0) {
      const char *cwd_value = (const char *)cwd;
      if (cwd_value != NULL && cwd_value[0] != '\0') {
        chdir(cwd_value);
      }
      dup2(stdin_pipe[0], STDIN_FILENO);
      dup2(stdout_pipe[1], STDOUT_FILENO);
      close(stdin_pipe[0]);
      close(stdin_pipe[1]);
      close(stdout_pipe[0]);
      close(stdout_pipe[1]);
      execl("/bin/sh", "sh", "-c", (const char *)command_line, (char *)NULL);
      _exit(127);
    }
    close(stdin_pipe[0]);
    close(stdout_pipe[1]);
    transport->stdin_write = stdin_pipe[1];
    transport->stdout_read = stdout_pipe[0];
    if (transport->pid < 0) {
      transport->closed = 1;
    } else {
      int flags = fcntl(transport->stdout_read, F_GETFL, 0);
      fcntl(transport->stdout_read, F_SETFL, flags | O_NONBLOCK);
    }
  }
#endif
  return transport;
}

int32_t lepus_core_stdio_transport_is_open(
    struct lepus_core_stdio_transport *transport) {
  if (transport == NULL || transport->closed) {
    return 0;
  }
#ifdef _WIN32
  if (transport->process != NULL &&
      WaitForSingleObject(transport->process, 0) == WAIT_OBJECT_0) {
    transport->closed = 1;
    return 0;
  }
#else
  if (transport->pid > 0) {
    int status = 0;
    pid_t result = waitpid(transport->pid, &status, WNOHANG);
    if (result == transport->pid) {
      transport->closed = 1;
      return 0;
    }
  }
#endif
  return 1;
}

int32_t lepus_core_stdio_transport_write(
    struct lepus_core_stdio_transport *transport,
    moonbit_bytes_t request_json) {
  size_t len;
  if (!lepus_core_stdio_transport_is_open(transport) || request_json == NULL) {
    return 0;
  }
  len = strlen((const char *)request_json);
#ifdef _WIN32
  {
    DWORD written = 0;
    return WriteFile(
               transport->stdin_write,
               request_json,
               (DWORD)len,
               &written,
               NULL) &&
           written == len;
  }
#else
  {
    ssize_t written = write(transport->stdin_write, request_json, len);
    return written == (ssize_t)len;
  }
#endif
}

moonbit_bytes_t lepus_core_stdio_transport_read_line(
    struct lepus_core_stdio_transport *transport) {
  moonbit_bytes_t line;
  if (transport == NULL || transport->closed) {
    return lepus_core_cstr_bytes("");
  }
  line = lepus_core_stdio_transport_take_line(transport);
  if (((char *)line)[0] != '\0') {
    return line;
  }
#ifdef _WIN32
  {
    DWORD available = 0;
    DWORD read_len = 0;
    char chunk[4096];
    if (!PeekNamedPipe(
            transport->stdout_read,
            NULL,
            0,
            NULL,
            &available,
            NULL)) {
      transport->closed = 1;
      return lepus_core_cstr_bytes("");
    }
    if (available == 0) {
      return lepus_core_cstr_bytes("");
    }
    if (available > sizeof(chunk)) {
      available = sizeof(chunk);
    }
    if (!ReadFile(
            transport->stdout_read,
            chunk,
            available,
            &read_len,
            NULL)) {
      transport->closed = 1;
      return lepus_core_cstr_bytes("");
    }
    if (read_len > 0 &&
        lepus_core_stdio_transport_reserve(transport, (size_t)read_len)) {
      memcpy(transport->buffer + transport->buffer_len, chunk, read_len);
      transport->buffer_len += read_len;
    }
  }
#else
  {
    char chunk[4096];
    ssize_t read_len = read(transport->stdout_read, chunk, sizeof(chunk));
    if (read_len > 0 &&
        lepus_core_stdio_transport_reserve(transport, (size_t)read_len)) {
      memcpy(transport->buffer + transport->buffer_len, chunk, (size_t)read_len);
      transport->buffer_len += (size_t)read_len;
    } else if (read_len == 0) {
      transport->closed = 1;
    } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
      transport->closed = 1;
    }
  }
#endif
  return lepus_core_stdio_transport_take_line(transport);
}

void lepus_core_stdio_transport_close(
    struct lepus_core_stdio_transport *transport) {
  if (transport == NULL || transport->closed) {
    return;
  }
  transport->closed = 1;
#ifdef _WIN32
  if (transport->stdin_write != NULL) {
    CloseHandle(transport->stdin_write);
    transport->stdin_write = NULL;
  }
  if (transport->stdout_read != NULL) {
    CloseHandle(transport->stdout_read);
    transport->stdout_read = NULL;
  }
  if (transport->process != NULL) {
    TerminateProcess(transport->process, 0);
    CloseHandle(transport->process);
    transport->process = NULL;
  }
#else
  if (transport->stdin_write >= 0) {
    close(transport->stdin_write);
    transport->stdin_write = -1;
  }
  if (transport->stdout_read >= 0) {
    close(transport->stdout_read);
    transport->stdout_read = -1;
  }
  if (transport->pid > 0) {
    kill(transport->pid, SIGTERM);
    waitpid(transport->pid, NULL, 0);
    transport->pid = -1;
  }
#endif
}

static void lepus_core_stdio_transport_finalize(void *raw_transport) {
  struct lepus_core_stdio_transport *transport =
      (struct lepus_core_stdio_transport *)raw_transport;
  if (transport == NULL) {
    return;
  }
  lepus_core_stdio_transport_close(transport);
  free(transport->buffer);
  transport->buffer = NULL;
  transport->buffer_len = 0;
  transport->buffer_cap = 0;
}
