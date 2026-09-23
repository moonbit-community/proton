#if defined(_WIN32)
#include "../../src/engine/cef_win/win_internal.h"
#include <wchar.h>

#define CONSENT L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore"
#define CHECK(c) do { if (!(c)) { result = __LINE__; goto cleanup; } } while (0)

static int set_consent(HKEY root, const wchar_t *path, const wchar_t *value) {
  HKEY key = NULL;
  if (RegCreateKeyExW(root, path, 0, NULL, REG_OPTION_VOLATILE,
                      KEY_ALL_ACCESS, NULL, &key, NULL) != ERROR_SUCCESS) {
    return 0;
  }
  LSTATUS status = value == NULL
      ? RegDeleteValueW(key, L"Value")
      : RegSetValueExW(key, L"Value", 0, REG_SZ, (const BYTE *)value,
                       (DWORD)((wcslen(value) + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return status == ERROR_SUCCESS || (value == NULL && status == ERROR_FILE_NOT_FOUND);
}

/* Redirect only this test process's predefined keys to volatile fixtures.
 * Never write the user's real ConsentStore or require administrator access. */
int32_t proton_test_desktop_media_consent(void) {
  int result = 0;
  HKEY real_user = NULL, fixture = NULL, user = NULL, machine = NULL;
  int user_redirected = 0, machine_redirected = 0;
  wchar_t fixture_path[128];
  swprintf(fixture_path, 128, L"Software\\ProtonConsentTest-%lu-%llu",
           GetCurrentProcessId(), (unsigned long long)GetTickCount64());
  CHECK(RegOpenCurrentUser(KEY_ALL_ACCESS, &real_user) == ERROR_SUCCESS);
  CHECK(RegCreateKeyExW(real_user, fixture_path, 0, NULL, REG_OPTION_VOLATILE,
                        KEY_ALL_ACCESS, NULL, &fixture, NULL) == ERROR_SUCCESS);
  CHECK(RegCreateKeyExW(fixture, L"User", 0, NULL, REG_OPTION_VOLATILE,
                        KEY_ALL_ACCESS, NULL, &user, NULL) == ERROR_SUCCESS);
  CHECK(RegCreateKeyExW(fixture, L"Machine", 0, NULL, REG_OPTION_VOLATILE,
                        KEY_ALL_ACCESS, NULL, &machine, NULL) == ERROR_SUCCESS);
  CHECK(RegOverridePredefKey(HKEY_CURRENT_USER, user) == ERROR_SUCCESS);
  user_redirected = 1;
  CHECK(RegOverridePredefKey(HKEY_LOCAL_MACHINE, machine) == ERROR_SUCCESS);
  machine_redirected = 1;
  wchar_t exe[4096];
  DWORD length = GetModuleFileNameW(NULL, exe, 4096);
  CHECK(length > 0 && length < 4096);
  for (DWORD i = 0; i < length; ++i) if (exe[i] == L'\\') exe[i] = L'#';
  const struct {
    const wchar_t *machine, *device, *desktop, *app;
    int32_t expected;
  } cases[] = {
    {NULL, L"Allow", L"Deny", NULL, PROTON_MEDIA_ACCESS_STATUS_DENIED},
    {NULL, L"Allow", L"Deny", L"Allow", PROTON_MEDIA_ACCESS_STATUS_DENIED},
    {L"Deny", L"Allow", L"Allow", L"Allow", PROTON_MEDIA_ACCESS_STATUS_RESTRICTED},
    {NULL, L"Deny", L"Allow", L"Allow", PROTON_MEDIA_ACCESS_STATUS_DENIED},
    {NULL, L"Allow", L"Allow", L"Deny", PROTON_MEDIA_ACCESS_STATUS_DENIED},
    {NULL, L"Allow", L"Allow", NULL, PROTON_MEDIA_ACCESS_STATUS_GRANTED},
    {NULL, NULL, L"Allow", NULL, PROTON_MEDIA_ACCESS_STATUS_GRANTED},
    {NULL, L"Allow", NULL, NULL, PROTON_MEDIA_ACCESS_STATUS_GRANTED},
    {NULL, NULL, NULL, L"Allow", PROTON_MEDIA_ACCESS_STATUS_GRANTED},
    {NULL, NULL, NULL, NULL, PROTON_MEDIA_ACCESS_STATUS_NOT_DETERMINED},
    {NULL, NULL, L"Unexpected", NULL, PROTON_MEDIA_ACCESS_STATUS_NOT_DETERMINED},
    {NULL, L"Allow", L"dEnY", NULL, PROTON_MEDIA_ACCESS_STATUS_DENIED},
  };
  const wchar_t *names[] = {L"microphone", L"webcam"};
  const int32_t media[] = {PROTON_MEDIA_ACCESS_MICROPHONE, PROTON_MEDIA_ACCESS_CAMERA};
  for (int m = 0; m < 2; ++m) {
    wchar_t device[256], desktop[256], app[4352];
    swprintf(device, 256, L"%s\\%s", CONSENT, names[m]);
    swprintf(desktop, 256, L"%s\\NonPackaged", device);
    swprintf(app, 4352, L"%s\\%s", desktop, exe);
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
      CHECK(set_consent(machine, device, cases[i].machine));
      CHECK(set_consent(user, device, cases[i].device));
      CHECK(set_consent(user, desktop, cases[i].desktop));
      CHECK(set_consent(user, app, cases[i].app));
      int32_t status = -1;
      char error[256] = {0};
      CHECK(proton_engine_system_media_access_status(media[m], &status, error,
                                                      sizeof(error)) == PROTON_OK);
      CHECK(status == cases[i].expected);
    }
  }
cleanup:
  if (machine_redirected) RegOverridePredefKey(HKEY_LOCAL_MACHINE, NULL);
  if (user_redirected) RegOverridePredefKey(HKEY_CURRENT_USER, NULL);
  if (machine != NULL) RegCloseKey(machine);
  if (user != NULL) RegCloseKey(user);
  if (fixture != NULL) RegCloseKey(fixture);
  if (real_user != NULL) {
    RegDeleteTreeW(real_user, fixture_path);
    RegCloseKey(real_user);
  }
  return result;
}
#endif
