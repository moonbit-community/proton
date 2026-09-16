#include "proton_menu.h"

#include <moonbit.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static char *proton_menu_copy_string(const char *value) {
  if (value == NULL || value[0] == '\0')
    return NULL;
  size_t len = strlen(value);
  char *copy = malloc(len + 1);
  if (copy != NULL)
    memcpy(copy, value, len + 1);
  return copy;
}

static void proton_menu_destroy(proton_menu_t *menu) {
  if (menu == NULL)
    return;
  for (size_t i = 0; i < menu->item_count; i++) {
    proton_menu_item_t *item = &menu->items[i];
    free(item->id);
    free(item->label);
    free(item->key);
    free(item->role);
    proton_menu_destroy(item->submenu);
    free(item->submenu);
  }
  free(menu->items);
  free(menu->label);
}

static void proton_menu_config_finalize(void *payload) {
  proton_menu_bar_t *bar = payload;
  for (size_t i = 0; i < bar->menu_count; i++)
    proton_menu_destroy(&bar->menus[i]);
  free(bar->menus);
}

/* Native engines own independent copies; MoonBit owns the builder storage. */
void proton_menu_bar_destroy(proton_menu_bar_t *bar) {
  if (bar == NULL)
    return;
  proton_menu_config_finalize(bar);
  free(bar);
}

proton_menu_bar_t *proton_internal_menu_config_create(void) {
  proton_menu_bar_t *bar =
      moonbit_make_external_object(proton_menu_config_finalize, sizeof(*bar));
  memset(bar, 0, sizeof(*bar));
  return bar;
}

proton_menu_t *proton_internal_menu_node_null(void) { return NULL; }

int32_t proton_internal_menu_config_add_menu(proton_menu_bar_t *bar,
                                             const char *label, int32_t role,
                                             proton_menu_t **out_menu) {
  proton_menu_t *menus =
      realloc(bar->menus, (bar->menu_count + 1) * sizeof(*menus));
  if (menus == NULL)
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate menu definition");
  bar->menus = menus;
  proton_menu_t *menu = &bar->menus[bar->menu_count];
  memset(menu, 0, sizeof(*menu));
  menu->label = proton_menu_copy_string(label);
  if (menu->label == NULL)
    return proton_set_error(PROTON_ERR_ENGINE, "failed to copy menu label");
  menu->role = (proton_menu_role_t)role;
  bar->menu_count++;
  *out_menu = menu;
  return PROTON_OK;
}

static bool proton_menu_copy_item(proton_menu_item_t *item, const char *id,
                                  const char *label, const char *key,
                                  const char *role) {
  item->id = proton_menu_copy_string(id);
  item->label = proton_menu_copy_string(label);
  item->key = proton_menu_copy_string(key);
  item->role = proton_menu_copy_string(role);
  return !(id && id[0] && !item->id) && !(label && label[0] && !item->label) &&
         !(key && key[0] && !item->key) && !(role && role[0] && !item->role);
}

int32_t proton_internal_menu_config_add_item(proton_menu_bar_t *owner,
                                             proton_menu_t *menu, int32_t kind,
                                             const char *id, const char *label,
                                             const char *key, const char *role,
                                             int32_t enabled, int32_t visible,
                                             int32_t checkable, int32_t checked,
                                             proton_menu_t **out_submenu) {
  /* The borrowed owner keeps menu alive for this call. Traversal is MoonBit's.
   */
  (void)owner;
  proton_menu_item_t *items =
      realloc(menu->items, (menu->item_count + 1) * sizeof(*items));
  if (items == NULL)
    return proton_set_error(PROTON_ERR_ENGINE, "failed to allocate menu item");
  menu->items = items;
  proton_menu_item_t *item = &items[menu->item_count++];
  memset(item, 0, sizeof(*item));
  item->kind = (proton_menu_item_kind_t)kind;
  item->enabled = enabled;
  item->visible = visible;
  item->checkable = checkable;
  item->checked = checked;
  if (!proton_menu_copy_item(item, id, label, key, role))
    return proton_set_error(PROTON_ERR_ENGINE, "failed to copy menu item");
  *out_submenu = NULL;
  if (kind == PROTON_MENU_ITEM_SUBMENU) {
    item->submenu = calloc(1, sizeof(*item->submenu));
    if (item->submenu == NULL)
      return proton_set_error(PROTON_ERR_ENGINE, "failed to allocate submenu");
    item->submenu->label = proton_menu_copy_string(label);
    if (item->submenu->label == NULL)
      return proton_set_error(PROTON_ERR_ENGINE,
                              "failed to copy submenu label");
    *out_submenu = item->submenu;
  }
  return PROTON_OK;
}

/* Copies only native storage; it does not replay the MoonBit builder protocol.
 */
static bool proton_menu_clone(const proton_menu_t *source,
                              proton_menu_t *copy) {
  copy->label = proton_menu_copy_string(source->label);
  copy->role = source->role;
  if (source->label != NULL && copy->label == NULL)
    return false;
  if (source->item_count == 0)
    return true;
  copy->items = calloc(source->item_count, sizeof(*copy->items));
  if (copy->items == NULL)
    return false;
  for (size_t i = 0; i < source->item_count; i++) {
    const proton_menu_item_t *item = &source->items[i];
    proton_menu_item_t *target = &copy->items[copy->item_count++];
    target->kind = item->kind;
    target->enabled = item->enabled;
    target->visible = item->visible;
    target->checkable = item->checkable;
    target->checked = item->checked;
    if (!proton_menu_copy_item(target, item->id, item->label, item->key,
                               item->role))
      return false;
    if (item->submenu != NULL) {
      target->submenu = calloc(1, sizeof(*target->submenu));
      if (target->submenu == NULL ||
          !proton_menu_clone(item->submenu, target->submenu))
        return false;
    }
  }
  return true;
}

proton_menu_bar_t *proton_menu_bar_clone(const proton_menu_bar_t *source) {
  if (source == NULL)
    return NULL;
  proton_menu_bar_t *copy = calloc(1, sizeof(*copy));
  if (copy == NULL)
    return NULL;
  if (source->menu_count == 0)
    return copy;
  copy->menus = calloc(source->menu_count, sizeof(*copy->menus));
  if (copy->menus == NULL) {
    free(copy);
    return NULL;
  }
  for (size_t i = 0; i < source->menu_count; i++) {
    copy->menu_count++;
    if (!proton_menu_clone(&source->menus[i], &copy->menus[i])) {
      proton_menu_bar_destroy(copy);
      return NULL;
    }
  }
  return copy;
}
