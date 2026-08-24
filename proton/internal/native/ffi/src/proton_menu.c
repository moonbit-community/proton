#include "proton_menu.h"

#include <stdlib.h>
#include <string.h>

static char *proton_menu_copy_string(const char *value) {
  if (value == NULL || value[0] == '\0') {
    return NULL;
  }
  size_t len = strlen(value);
  char *copy = (char *)malloc(len + 1);
  if (copy != NULL) {
    memcpy(copy, value, len + 1);
  }
  return copy;
}

static void proton_menu_item_dispose(proton_menu_item_t *item) {
  if (item == NULL) {
    return;
  }
  free(item->id);
  free(item->label);
  free(item->key);
  free(item->role);
  memset(item, 0, sizeof(*item));
}

void proton_menu_bar_destroy(proton_menu_bar_t *menu_bar) {
  if (menu_bar == NULL) {
    return;
  }
  for (size_t menu_index = 0; menu_index < menu_bar->menu_count;
       menu_index++) {
    proton_menu_t *menu = &menu_bar->menus[menu_index];
    for (size_t item_index = 0; item_index < menu->item_count; item_index++) {
      proton_menu_item_dispose(&menu->items[item_index]);
    }
    free(menu->items);
    free(menu->label);
  }
  free(menu_bar->menus);
  free(menu_bar);
}

static int proton_menu_role_supported(const char *role) {
  static const char *const roles[] = {
      "quit",   "hide", "hide_others", "show_all", "close",
      "minimize", "zoom", "undo",        "redo",     "cut",
      "copy",   "paste", "select_all",
  };
  if (role == NULL || role[0] == '\0') {
    return 0;
  }
  for (size_t index = 0; index < sizeof(roles) / sizeof(roles[0]); index++) {
    if (strcmp(role, roles[index]) == 0) {
      return 1;
    }
  }
  return 0;
}

proton_menu_bar_t *proton_internal_menu_config_null(void) { return NULL; }

int32_t proton_internal_menu_config_create(
    proton_menu_bar_t **out_menu_bar) {
  if (out_menu_bar == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu config output is required");
  }
  *out_menu_bar = (proton_menu_bar_t *)calloc(1, sizeof(**out_menu_bar));
  if (*out_menu_bar == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate menu config");
  }
  return PROTON_OK;
}

int32_t proton_internal_menu_config_add_menu(
    proton_menu_bar_t *menu_bar, const char *label, int32_t role,
    int32_t *out_menu_index) {
  if (menu_bar == NULL || label == NULL || label[0] == '\0' ||
      role < PROTON_MENU_ROLE_NONE || role > PROTON_MENU_ROLE_HELP ||
      out_menu_index == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu label and index output are required");
  }
  proton_menu_t *menus = (proton_menu_t *)realloc(
      menu_bar->menus, (menu_bar->menu_count + 1) * sizeof(*menus));
  if (menus == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate menu definition");
  }
  menu_bar->menus = menus;
  proton_menu_t *menu = &menu_bar->menus[menu_bar->menu_count];
  memset(menu, 0, sizeof(*menu));
  menu->label = proton_menu_copy_string(label);
  menu->role = (proton_menu_role_t)role;
  if (menu->label == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to copy menu label");
  }
  *out_menu_index = (int32_t)menu_bar->menu_count;
  menu_bar->menu_count++;
  return PROTON_OK;
}

int32_t proton_internal_menu_config_add_item(
    proton_menu_bar_t *menu_bar, int32_t menu_index, int32_t kind,
    const char *id, const char *label, const char *key, const char *role) {
  if (menu_bar == NULL || menu_index < 0 ||
      (size_t)menu_index >= menu_bar->menu_count || kind < PROTON_MENU_ITEM_COMMAND ||
      kind > PROTON_MENU_ITEM_ROLE) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu item is invalid");
  }
  if (kind == PROTON_MENU_ITEM_COMMAND &&
      (id == NULL || id[0] == '\0' || label == NULL || label[0] == '\0')) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu command requires id and label");
  }
  if (kind == PROTON_MENU_ITEM_ROLE && !proton_menu_role_supported(role)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu role is unsupported");
  }

  proton_menu_t *menu = &menu_bar->menus[menu_index];
  proton_menu_item_t *items = (proton_menu_item_t *)realloc(
      menu->items, (menu->item_count + 1) * sizeof(*items));
  if (items == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate menu item");
  }
  menu->items = items;
  proton_menu_item_t item = {
      .kind = (proton_menu_item_kind_t)kind,
      .id = proton_menu_copy_string(id),
      .label = proton_menu_copy_string(label),
      .key = proton_menu_copy_string(key),
      .role = proton_menu_copy_string(role),
  };
  if ((id != NULL && id[0] != '\0' && item.id == NULL) ||
      (label != NULL && label[0] != '\0' && item.label == NULL) ||
      (key != NULL && key[0] != '\0' && item.key == NULL) ||
      (role != NULL && role[0] != '\0' && item.role == NULL)) {
    proton_menu_item_dispose(&item);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to copy menu item");
  }
  menu->items[menu->item_count++] = item;
  return PROTON_OK;
}

proton_menu_bar_t *proton_menu_bar_clone(const proton_menu_bar_t *menu_bar) {
  if (menu_bar == NULL) {
    return NULL;
  }
  proton_menu_bar_t *copy = NULL;
  if (proton_internal_menu_config_create(&copy) != PROTON_OK) {
    return NULL;
  }
  for (size_t menu_index = 0; menu_index < menu_bar->menu_count; menu_index++) {
    const proton_menu_t *menu = &menu_bar->menus[menu_index];
    int32_t copied_index = 0;
    if (proton_internal_menu_config_add_menu(copy, menu->label, menu->role,
                                             &copied_index) != PROTON_OK) {
      proton_menu_bar_destroy(copy);
      return NULL;
    }
    for (size_t item_index = 0; item_index < menu->item_count; item_index++) {
      const proton_menu_item_t *item = &menu->items[item_index];
      if (proton_internal_menu_config_add_item(
              copy, copied_index, item->kind, item->id, item->label, item->key,
              item->role) != PROTON_OK) {
        proton_menu_bar_destroy(copy);
        return NULL;
      }
    }
  }
  return copy;
}

void proton_internal_menu_config_destroy(proton_menu_bar_t *menu_bar) {
  proton_menu_bar_destroy(menu_bar);
}
