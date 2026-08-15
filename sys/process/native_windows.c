#include "native_stub.h"

#ifdef _WIN32

#include <stdio.h>
#include <string.h>

#define UNICODE 1
#define _UNICODE 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static wchar_t *utf8_to_wide(const char *utf8) {
  if (utf8 == NULL) {
    return NULL;
  }
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
  if (len <= 0) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)malloc((size_t)len * sizeof(wchar_t));
  if (wide == NULL) {
    return NULL;
  }
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, len);
  return wide;
}

static wchar_t *build_command_line(const char *command, const char *args) {
  /* Build a Windows command line: "command" args */
  wchar_t *w_cmd = utf8_to_wide(command);
  if (w_cmd == NULL) {
    return NULL;
  }
  wchar_t *w_args = NULL;
  if (args != NULL && args[0] != '\0') {
    w_args = utf8_to_wide(args);
  }

  size_t cmd_len = wcslen(w_cmd);
  size_t args_len = w_args ? wcslen(w_args) : 0;
  /* "cmd" + space + args + null */
  size_t total = cmd_len + args_len + 4;
  wchar_t *cmdline = (wchar_t *)malloc(total * sizeof(wchar_t));
  if (cmdline == NULL) {
    free(w_cmd);
    free(w_args);
    return NULL;
  }
  cmdline[0] = L'"';
  wcscpy(cmdline + 1, w_cmd);
  cmdline[cmd_len + 1] = L'"';
  if (w_args != NULL && args_len > 0) {
    cmdline[cmd_len + 2] = L' ';
    wcscpy(cmdline + cmd_len + 3, w_args);
  } else {
    cmdline[cmd_len + 2] = L'\0';
  }
  free(w_cmd);
  free(w_args);
  return cmdline;
}

int32_t process_platform_spawn(process_state_t *state,
                               const char *command,
                               const char *args,
                               const char *cwd,
                               int32_t capture_output) {
  (void)capture_output;
  wchar_t *cmdline = build_command_line(command, args);
  if (cmdline == NULL) {
    snprintf(state->last_error, sizeof(state->last_error),
             "failed to build command line");
    return process_STATUS_OPERATION_FAILED;
  }

  wchar_t *w_cwd = utf8_to_wide(cwd);

  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  ZeroMemory(&pi, sizeof(pi));

  DWORD creation_flags = 0;
  if (!CreateProcessW(NULL, cmdline, NULL, NULL, FALSE, creation_flags,
                     NULL, w_cwd, &si, &pi)) {
    DWORD err = GetLastError();
    snprintf(state->last_error, sizeof(state->last_error),
             "CreateProcessW failed (error %lu)", (unsigned long)err);
    free(cmdline);
    free(w_cwd);
    return process_STATUS_OPERATION_FAILED;
  }

  state->pid = (int32_t)pi.dwProcessId;
  state->h_process = pi.hProcess;
  state->h_thread = pi.hThread;
  free(cmdline);
  free(w_cwd);
  return process_STATUS_OK;
}

int32_t process_platform_try_wait(process_state_t *state,
                                  int32_t *out_exit_code,
                                  int32_t *out_exited) {
  if (state->h_process == NULL) {
    *out_exited = 1;
    *out_exit_code = state->exit_code;
    return process_STATUS_OK;
  }
  DWORD result = WaitForSingleObject((HANDLE)state->h_process, 0);
  if (result == WAIT_TIMEOUT) {
    *out_exited = 0;
    return process_STATUS_OK;
  }
  if (result == WAIT_FAILED) {
    snprintf(state->last_error, sizeof(state->last_error),
             "WaitForSingleObject failed");
    return process_STATUS_OPERATION_FAILED;
  }
  DWORD code = 0;
  GetExitCodeProcess((HANDLE)state->h_process, &code);
  state->exit_code = (int32_t)code;
  state->exited = 1;
  *out_exit_code = (int32_t)code;
  *out_exited = 1;
  return process_STATUS_OK;
}

int32_t process_platform_kill(process_state_t *state) {
  if (state->h_process == NULL) {
    return process_STATUS_OK;
  }
  if (!TerminateProcess((HANDLE)state->h_process, 1)) {
    DWORD err = GetLastError();
    if (err != ERROR_ACCESS_DENIED) {
      snprintf(state->last_error, sizeof(state->last_error),
               "TerminateProcess failed (error %lu)", (unsigned long)err);
      return process_STATUS_OPERATION_FAILED;
    }
  }
  return process_STATUS_OK;
}

void process_platform_cleanup(process_state_t *state) {
  if (state->h_process != NULL) {
    CloseHandle((HANDLE)state->h_process);
    state->h_process = NULL;
  }
  if (state->h_thread != NULL) {
    CloseHandle((HANDLE)state->h_thread);
    state->h_thread = NULL;
  }
}

void process_platform_sleep_ms(int32_t ms) {
  Sleep((DWORD)ms);
}

#endif /* _WIN32 */
