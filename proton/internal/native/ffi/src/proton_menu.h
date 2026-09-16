#ifndef PROTON_MENU_H
#define PROTON_MENU_H

#include "proton_internal.h"

#include <stddef.h>
#include <stdint.h>

typedef enum {
  PROTON_MENU_ITEM_COMMAND = 0,
  PROTON_MENU_ITEM_SEPARATOR = 1,
  PROTON_MENU_ITEM_ROLE = 2,
  PROTON_MENU_ITEM_SUBMENU = 3,
} proton_menu_item_kind_t;

typedef enum {
  PROTON_MENU_ROLE_NONE = 0,
  PROTON_MENU_ROLE_APPLICATION = 1,
  PROTON_MENU_ROLE_FILE = 2,
  PROTON_MENU_ROLE_EDIT = 3,
  PROTON_MENU_ROLE_VIEW = 4,
  PROTON_MENU_ROLE_WINDOW = 5,
  PROTON_MENU_ROLE_HELP = 6,
} proton_menu_role_t;

typedef struct proton_menu proton_menu_t;

typedef struct {
  proton_menu_item_kind_t kind;
  char *id;
  char *label;
  char *key;
  char *role;
  int enabled;
  int visible;
  int checkable;
  int checked;
  /* Owned nested menu; NULL unless `kind` is PROTON_MENU_ITEM_SUBMENU. */
  proton_menu_t *submenu;
} proton_menu_item_t;

struct proton_menu {
  char *label;
  proton_menu_role_t role;
  proton_menu_item_t *items;
  size_t item_count;
};

typedef struct proton_menu_bar {
  proton_menu_t *menus;
  size_t menu_count;
} proton_menu_bar_t;

PROTON_INTERNAL proton_menu_bar_t *proton_menu_bar_clone(
    const proton_menu_bar_t *menu_bar);
PROTON_INTERNAL void proton_menu_bar_destroy(proton_menu_bar_t *menu_bar);

/* Managed MoonBit payload; native engines retain only independent clones. */
PROTON_INTERNAL proton_menu_bar_t *proton_internal_menu_config_create(void);
PROTON_INTERNAL int32_t proton_internal_menu_config_add_menu(
    proton_menu_bar_t *menu_bar, const char *label, int32_t role,
    proton_menu_t **out_menu);
/* Node pointers are borrowed from the owner, never independently retained. */
PROTON_INTERNAL proton_menu_t *proton_internal_menu_node_null(void);
PROTON_INTERNAL int32_t proton_internal_menu_config_add_item(
    proton_menu_bar_t *owner, proton_menu_t *menu, int32_t kind,
    const char *id, const char *label, const char *key, const char *role,
    int32_t enabled, int32_t visible, int32_t checkable, int32_t checked,
    proton_menu_t **out_submenu);

#endif
