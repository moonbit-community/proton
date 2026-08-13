#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)

#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

void power_monitor_platform_init(power_monitor_state_t *state) {
  (void)state;
}

int32_t power_monitor_platform_query_idle(power_monitor_state_t *state) {
  state->idle_seconds = 0;
  return power_monitor_STATUS_OK;
}

static int read_int_from_file(const char *path) {
  FILE *f = fopen(path, "r");
  if (f == NULL) {
    return -1;
  }
  int value = -1;
  if (fscanf(f, "%d", &value) != 1) {
    value = -1;
  }
  fclose(f);
  return value;
}

int32_t power_monitor_platform_query_source(power_monitor_state_t *state) {
  DIR *dir = opendir("/sys/class/power_supply");
  if (dir == NULL) {
    state->source = power_monitor_SOURCE_UNKNOWN;
    state->has_battery_percent = 0;
    return power_monitor_STATUS_OK;
  }
  state->source = power_monitor_SOURCE_AC;
  state->has_battery_percent = 0;
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_name[0] == '.') {
      continue;
    }
    char type_path[512];
    char online_path[512];
    char capacity_path[512];
    snprintf(type_path, sizeof(type_path), "/sys/class/power_supply/%s/type",
             entry->d_name);
    snprintf(online_path, sizeof(online_path),
             "/sys/class/power_supply/%s/online", entry->d_name);
    snprintf(capacity_path, sizeof(capacity_path),
             "/sys/class/power_supply/%s/capacity", entry->d_name);

    FILE *type_f = fopen(type_path, "r");
    if (type_f == NULL) {
      continue;
    }
    char type_buf[32] = {0};
    if (fgets(type_buf, sizeof(type_buf), type_f) == NULL) {
      fclose(type_f);
      continue;
    }
    fclose(type_f);
    type_buf[strcspn(type_buf, "\n")] = '\0';

    if (strcmp(type_buf, "Mains") == 0) {
      int online = read_int_from_file(online_path);
      if (online == 1) {
        state->source = power_monitor_SOURCE_AC;
      }
    } else if (strcmp(type_buf, "Battery") == 0) {
      int capacity = read_int_from_file(capacity_path);
      if (capacity >= 0 && capacity <= 100) {
        state->battery_percent = capacity;
        state->has_battery_percent = 1;
      }
      int online = read_int_from_file(online_path);
      if (online == 0 && state->source != power_monitor_SOURCE_AC) {
        state->source = power_monitor_SOURCE_BATTERY;
      }
    }
  }
  closedir(dir);
  return power_monitor_STATUS_OK;
}

#endif
