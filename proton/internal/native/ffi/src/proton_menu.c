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

static void proton_menu_bar_reset_build_state(proton_menu_bar_t *menu_bar) {
  free(menu_bar->build_stack);
  menu_bar->build_stack = NULL;
  menu_bar->build_stack_len = 0;
  menu_bar->build_stack_cap = 0;
  menu_bar->build_target = NULL;
}

static void proton_menu_destroy(proton_menu_t *menu) {
  if (menu == NULL) {
    return;
  }
  for (size_t item_index = 0; item_index < menu->item_count; item_index++) {
    proton_menu_item_t *item = &menu->items[item_index];
    free(item->id);
    free(item->label);
    free(item->key);
    free(item->role);
    proton_menu_destroy(item->submenu);
  }
  free(menu->items);
  free(menu->label);
}

void proton_menu_bar_destroy(proton_menu_bar_t *menu_bar) {
  if (menu_bar == NULL) {
    return;
  }
  for (size_t menu_index = 0; menu_index < menu_bar->menu_count;
       menu_index++) {
    proton_menu_destroy(&menu_bar->menus[menu_index]);
  }
  free(menu_bar->menus);
  proton_menu_bar_reset_build_state(menu_bar);
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
  menu_bar->build_target = menu;
  return PROTON_OK;
}

/* The current item-append target is always non-NULL during building: either a
   top-level menu (after `add_menu`) or a nested submenu (after
   `begin_submenu`). */
static proton_menu_t *proton_menu_config_build_target(
    proton_menu_bar_t *menu_bar) {
  if (menu_bar == NULL || menu_bar->build_target == NULL) {
    return NULL;
  }
  return menu_bar->build_target;
}

static int32_t proton_menu_config_append_item(
    proton_menu_bar_t *menu_bar, int32_t kind, const char *id,
    const char *label, const char *key, const char *role,
    int32_t enabled, int32_t visible, int32_t checkable, int32_t checked,
    proton_menu_t *submenu) {
  proton_menu_t *menu = proton_menu_config_build_target(menu_bar);
  if (menu == NULL || kind < PROTON_MENU_ITEM_COMMAND ||
      kind > PROTON_MENU_ITEM_SUBMENU) {
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
  if (kind == PROTON_MENU_ITEM_SUBMENU &&
      (label == NULL || label[0] == '\0')) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu submenu requires a label");
  }

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
      .enabled = enabled != 0,
      .visible = visible != 0,
      .checkable = checkable != 0,
      .checked = checked != 0,
      .submenu = submenu,
  };
  if ((id != NULL && id[0] != '\0' && item.id == NULL) ||
      (label != NULL && label[0] != '\0' && item.label == NULL) ||
      (key != NULL && key[0] != '\0' && item.key == NULL) ||
      (role != NULL && role[0] != '\0' && item.role == NULL)) {
    free(item.id);
    free(item.label);
    free(item.key);
    free(item.role);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to copy menu item");
  }
  menu->items[menu->item_count++] = item;
  return PROTON_OK;
}

int32_t proton_internal_menu_config_add_item(
    proton_menu_bar_t *menu_bar, int32_t kind, const char *id,
    const char *label, const char *key, const char *role, int32_t enabled,
    int32_t visible, int32_t checkable, int32_t checked) {
  if (kind == PROTON_MENU_ITEM_SUBMENU) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "submenu item requires begin_submenu");
  }
  return proton_menu_config_append_item(menu_bar, kind, id, label, key, role,
                                        enabled, visible, checkable, checked,
                                        NULL);
}

int32_t proton_internal_menu_config_begin_submenu(
    proton_menu_bar_t *menu_bar, const char *label) {
  proton_menu_t *parent = proton_menu_config_build_target(menu_bar);
  if (parent == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "submenu requires an open menu");
  }
  proton_menu_t *submenu = (proton_menu_t *)calloc(1, sizeof(*submenu));
  if (submenu == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate submenu");
  }
  submenu->label = proton_menu_copy_string(label);
  if (submenu->label == NULL) {
    free(submenu);
    return proton_set_error(PROTON_ERR_ENGINE, "failed to copy submenu label");
  }

  /* Append the SUBMENU item to the current target (the parent) first, so its
     `submenu` member is reachable from the tree, then navigate into it. */
  int32_t status = proton_menu_config_append_item(
      menu_bar, PROTON_MENU_ITEM_SUBMENU, NULL, label, NULL, NULL, 1, 1, 0, 0,
      submenu);
  if (status != PROTON_OK) {
    proton_menu_destroy(submenu);
    return status;
  }

  if (menu_bar->build_stack_len == menu_bar->build_stack_cap) {
    size_t cap = menu_bar->build_stack_cap == 0
                     ? 8
                     : menu_bar->build_stack_cap * 2;
    proton_menu_t **stack = (proton_menu_t **)realloc(
        menu_bar->build_stack, cap * sizeof(*stack));
    if (stack == NULL) {
      /* Recover the previously appended item and roll back. */
      parent->item_count--;
      proton_menu_destroy(submenu);
      return proton_set_error(PROTON_ERR_ENGINE,
                              "failed to grow submenu stack");
    }
    menu_bar->build_stack = stack;
    menu_bar->build_stack_cap = cap;
  }
  menu_bar->build_stack[menu_bar->build_stack_len++] = parent;
  menu_bar->build_target = submenu;
  return PROTON_OK;
}

int32_t proton_internal_menu_config_end_submenu(
    proton_menu_bar_t *menu_bar) {
  if (menu_bar == NULL || menu_bar->build_stack_len == 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "no submenu is open");
  }
  menu_bar->build_target = menu_bar->build_stack[menu_bar->build_stack_len - 1];
  menu_bar->build_stack_len--;
  return PROTON_OK;
}

static int32_t proton_menu_clone_append_items(
    proton_menu_bar_t *builder, const proton_menu_t *source) {
  for (size_t item_index = 0; item_index < source->item_count; item_index++) {
    const proton_menu_item_t *item = &source->items[item_index];
    if (item->kind == PROTON_MENU_ITEM_SUBMENU) {
      const char *label = item->label != NULL ? item->label : "";
      if (proton_internal_menu_config_begin_submenu(builder, label) !=
          PROTON_OK) {
        return PROTON_ERR_ENGINE;
      }
      if (item->submenu != NULL &&
          proton_menu_clone_append_items(builder, item->submenu) != PROTON_OK) {
        return PROTON_ERR_ENGINE;
      }
      if (proton_internal_menu_config_end_submenu(builder) != PROTON_OK) {
        return PROTON_ERR_ENGINE;
      }
      continue;
    }
    if (proton_internal_menu_config_add_item(
            builder, item->kind, item->id, item->label, item->key,
            item->role, item->enabled, item->visible, item->checkable,
            item->checked) != PROTON_OK) {
      return PROTON_ERR_ENGINE;
    }
  }
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
    if (proton_menu_clone_append_items(copy, menu) != PROTON_OK) {
      proton_menu_bar_destroy(copy);
      return NULL;
    }
  }
  proton_menu_bar_reset_build_state(copy);
  return copy;
}

void proton_internal_menu_config_destroy(proton_menu_bar_t *menu_bar) {
  proton_menu_bar_destroy(menu_bar);
}
