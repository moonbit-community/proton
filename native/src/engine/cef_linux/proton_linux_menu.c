#include "proton_linux_menu.h"

#include "../../proton_json.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
  PROTON_LINUX_MENU_ITEM_COMMAND = 0,
  PROTON_LINUX_MENU_ITEM_SEPARATOR,
  PROTON_LINUX_MENU_ITEM_ROLE,
} proton_linux_menu_item_kind_t;

typedef struct {
  proton_linux_menu_item_kind_t kind;
  char *id;
  char *label;
  char *key;
  char *role;
} proton_linux_menu_item_t;

typedef struct {
  char *label;
  char *role;
  proton_linux_menu_item_t *items;
  size_t item_count;
} proton_linux_menu_t;

struct proton_linux_menu_bar {
  proton_linux_menu_t *menus;
  size_t menu_count;
};

typedef struct {
  proton_linux_menu_command_callback_t command_callback;
  proton_linux_menu_role_callback_t role_callback;
  void *user_data;
  char *value;
  int is_command;
} proton_linux_menu_activation_t;

typedef struct {
  const proton_json_doc_t *doc;
  proton_linux_menu_t *menu;
  char *error;
  size_t error_len;
} proton_linux_menu_item_parse_t;

typedef struct {
  const proton_json_doc_t *doc;
  proton_linux_menu_bar_t *menu_bar;
  char *error;
  size_t error_len;
} proton_linux_menu_parse_t;

static void proton_linux_menu_set_message(char *error,
                                          size_t error_len,
                                          const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static int proton_linux_menu_role_supported(const char *role) {
  static const char *roles[] = {
      "quit",   "hide", "hide_others", "show_all", "close",
      "minimize", "zoom", "undo",        "redo",     "cut",
      "copy",   "paste", "select_all",
  };
  if (role == NULL) {
    return 0;
  }
  for (size_t index = 0; index < sizeof(roles) / sizeof(roles[0]); index++) {
    if (strcmp(role, roles[index]) == 0) {
      return 1;
    }
  }
  return 0;
}

static void proton_linux_menu_item_dispose(proton_linux_menu_item_t *item) {
  if (item == NULL) {
    return;
  }
  free(item->id);
  free(item->label);
  free(item->key);
  free(item->role);
  memset(item, 0, sizeof(*item));
}

static void proton_linux_menu_dispose(proton_linux_menu_t *menu) {
  if (menu == NULL) {
    return;
  }
  for (size_t index = 0; index < menu->item_count; index++) {
    proton_linux_menu_item_dispose(&menu->items[index]);
  }
  free(menu->items);
  free(menu->label);
  free(menu->role);
  memset(menu, 0, sizeof(*menu));
}

void proton_linux_menu_bar_destroy(proton_linux_menu_bar_t *menu_bar) {
  if (menu_bar == NULL) {
    return;
  }
  for (size_t index = 0; index < menu_bar->menu_count; index++) {
    proton_linux_menu_dispose(&menu_bar->menus[index]);
  }
  free(menu_bar->menus);
  free(menu_bar);
}

static char *proton_linux_menu_optional_string(const proton_json_doc_t *doc,
                                               proton_json_value_t object,
                                               const char *field,
                                               int *out_valid) {
  proton_json_value_t value;
  if (!proton_json_object_get(doc, object, field, &value)) {
    return NULL;
  }
  char *text = proton_json_copy_string(doc, value);
  if (text == NULL) {
    *out_valid = 0;
  }
  return text;
}

static int proton_linux_menu_append_item(proton_linux_menu_t *menu,
                                         proton_linux_menu_item_t item) {
  proton_linux_menu_item_t *items =
      (proton_linux_menu_item_t *)realloc(
          menu->items, (menu->item_count + 1) * sizeof(*items));
  if (items == NULL) {
    return 0;
  }
  menu->items = items;
  menu->items[menu->item_count++] = item;
  return 1;
}

static bool proton_linux_menu_parse_item(proton_json_value_t value,
                                         void *user_data) {
  proton_linux_menu_item_parse_t *parse =
      (proton_linux_menu_item_parse_t *)user_data;
  if (!proton_json_is_object(parse->doc, value)) {
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu item must be an object");
    return false;
  }
  proton_json_value_t kind_value;
  char kind[32] = {0};
  if (!proton_json_object_get(parse->doc, value, "kind", &kind_value) ||
      !proton_json_read_string(parse->doc, kind_value, kind, sizeof(kind))) {
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu item requires kind");
    return false;
  }

  proton_linux_menu_item_t item = {0};
  int valid = 1;
  item.key =
      proton_linux_menu_optional_string(parse->doc, value, "key", &valid);
  if (!valid) {
    proton_linux_menu_item_dispose(&item);
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu item key must be a string");
    return false;
  }

  if (strcmp(kind, "separator") == 0) {
    item.kind = PROTON_LINUX_MENU_ITEM_SEPARATOR;
  } else if (strcmp(kind, "command") == 0) {
    item.kind = PROTON_LINUX_MENU_ITEM_COMMAND;
    item.id =
        proton_linux_menu_optional_string(parse->doc, value, "id", &valid);
    item.label = proton_linux_menu_optional_string(parse->doc, value, "label",
                                                   &valid);
    if (!valid || item.id == NULL || item.label == NULL) {
      proton_linux_menu_item_dispose(&item);
      proton_linux_menu_set_message(parse->error, parse->error_len,
                                    "menu command requires label and id");
      return false;
    }
  } else if (strcmp(kind, "role") == 0) {
    item.kind = PROTON_LINUX_MENU_ITEM_ROLE;
    item.role =
        proton_linux_menu_optional_string(parse->doc, value, "role", &valid);
    item.label = proton_linux_menu_optional_string(parse->doc, value, "label",
                                                   &valid);
    if (!valid || item.label == NULL ||
        !proton_linux_menu_role_supported(item.role)) {
      proton_linux_menu_item_dispose(&item);
      proton_linux_menu_set_message(parse->error, parse->error_len,
                                    "menu role is unsupported");
      return false;
    }
  } else {
    proton_linux_menu_item_dispose(&item);
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu item kind is unsupported");
    return false;
  }

  if (!proton_linux_menu_append_item(parse->menu, item)) {
    proton_linux_menu_item_dispose(&item);
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "failed to allocate menu item");
    return false;
  }
  return true;
}

static int proton_linux_menu_append_menu(proton_linux_menu_bar_t *menu_bar,
                                         proton_linux_menu_t menu) {
  proton_linux_menu_t *menus = (proton_linux_menu_t *)realloc(
      menu_bar->menus, (menu_bar->menu_count + 1) * sizeof(*menus));
  if (menus == NULL) {
    return 0;
  }
  menu_bar->menus = menus;
  menu_bar->menus[menu_bar->menu_count++] = menu;
  return 1;
}

static bool proton_linux_menu_parse_menu(proton_json_value_t value,
                                         void *user_data) {
  proton_linux_menu_parse_t *parse = (proton_linux_menu_parse_t *)user_data;
  if (!proton_json_is_object(parse->doc, value)) {
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu definition must be an object");
    return false;
  }
  proton_json_value_t label_value;
  proton_json_value_t items_value;
  if (!proton_json_object_get(parse->doc, value, "label", &label_value) ||
      !proton_json_object_get(parse->doc, value, "items", &items_value) ||
      !proton_json_is_array(parse->doc, items_value)) {
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu requires label and items");
    return false;
  }

  proton_linux_menu_t menu = {0};
  menu.label = proton_json_copy_string(parse->doc, label_value);
  int valid = 1;
  menu.role = proton_linux_menu_optional_string(
      parse->doc, value, "role", &valid);
  if (!valid || menu.label == NULL) {
    proton_linux_menu_dispose(&menu);
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "menu requires label and items");
    return false;
  }
  proton_linux_menu_item_parse_t item_parse = {
      .doc = parse->doc,
      .menu = &menu,
      .error = parse->error,
      .error_len = parse->error_len,
  };
  if (!proton_json_array_each(parse->doc, items_value,
                              proton_linux_menu_parse_item, &item_parse)) {
    proton_linux_menu_dispose(&menu);
    return false;
  }
  if (!proton_linux_menu_append_menu(parse->menu_bar, menu)) {
    proton_linux_menu_dispose(&menu);
    proton_linux_menu_set_message(parse->error, parse->error_len,
                                  "failed to allocate menu definition");
    return false;
  }
  return true;
}

proton_linux_menu_bar_t *proton_linux_menu_bar_parse(const char *menu_json,
                                                     char *error,
                                                     size_t error_len) {
  if (menu_json == NULL) {
    proton_linux_menu_set_message(error, error_len, "menu_json is required");
    return NULL;
  }
  proton_json_doc_t doc = {0};
  proton_json_value_t root;
  proton_json_value_t menus;
  if (!proton_json_parse(&doc, menu_json) ||
      !proton_json_root_object(&doc, &root)) {
    proton_json_dispose(&doc);
    proton_linux_menu_set_message(error, error_len,
                                  "menu config must be a JSON object");
    return NULL;
  }
  if (!proton_json_object_get(&doc, root, "menus", &menus) ||
      !proton_json_is_array(&doc, menus)) {
    proton_json_dispose(&doc);
    proton_linux_menu_set_message(error, error_len,
                                  "menu config requires menus array");
    return NULL;
  }

  proton_linux_menu_bar_t *menu_bar =
      (proton_linux_menu_bar_t *)calloc(1, sizeof(*menu_bar));
  if (menu_bar == NULL) {
    proton_json_dispose(&doc);
    proton_linux_menu_set_message(error, error_len,
                                  "failed to allocate menu config");
    return NULL;
  }
  proton_linux_menu_parse_t parse = {
      .doc = &doc,
      .menu_bar = menu_bar,
      .error = error,
      .error_len = error_len,
  };
  if (!proton_json_array_each(&doc, menus, proton_linux_menu_parse_menu,
                              &parse)) {
    proton_json_dispose(&doc);
    proton_linux_menu_bar_destroy(menu_bar);
    return NULL;
  }
  proton_json_dispose(&doc);
  return menu_bar;
}

static void proton_linux_menu_activation_destroy(gpointer data) {
  proton_linux_menu_activation_t *activation =
      (proton_linux_menu_activation_t *)data;
  if (activation != NULL) {
    free(activation->value);
    free(activation);
  }
}

static void proton_linux_menu_activate(GtkMenuItem *item, gpointer user_data) {
  (void)item;
  proton_linux_menu_activation_t *activation =
      (proton_linux_menu_activation_t *)user_data;
  if (activation == NULL) {
    return;
  }
  if (activation->is_command) {
    activation->command_callback(activation->value, activation->user_data);
  } else {
    activation->role_callback(activation->value, activation->user_data);
  }
}

static int proton_linux_menu_bind_activation(
    GtkWidget *item,
    const char *value,
    int is_command,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data) {
  proton_linux_menu_activation_t *activation =
      (proton_linux_menu_activation_t *)calloc(1, sizeof(*activation));
  if (activation == NULL) {
    return 0;
  }
  activation->value = strdup(value);
  if (activation->value == NULL) {
    free(activation);
    return 0;
  }
  activation->command_callback = command_callback;
  activation->role_callback = role_callback;
  activation->user_data = user_data;
  activation->is_command = is_command;
  g_object_set_data_full(G_OBJECT(item), "proton-menu-activation", activation,
                         proton_linux_menu_activation_destroy);
  g_signal_connect(item, "activate", G_CALLBACK(proton_linux_menu_activate),
                   activation);
  return 1;
}

static void proton_linux_menu_add_accelerator(GtkWidget *item,
                                              GtkAccelGroup *accelerators,
                                              const char *key,
                                              GdkModifierType extra_modifiers) {
  if (item == NULL || accelerators == NULL || key == NULL || key[0] == '\0') {
    return;
  }
  char specification[128];
  if (key[1] == '\0' && isupper((unsigned char)key[0])) {
    snprintf(specification, sizeof(specification), "<Primary><Shift>%c",
             tolower((unsigned char)key[0]));
  } else {
    snprintf(specification, sizeof(specification), "<Primary>%s", key);
  }
  guint accelerator_key = 0;
  GdkModifierType modifiers = 0;
  gtk_accelerator_parse(specification, &accelerator_key, &modifiers);
  if (accelerator_key != 0) {
    gtk_widget_add_accelerator(item, "activate", accelerators,
                               accelerator_key, modifiers | extra_modifiers,
                               GTK_ACCEL_VISIBLE);
  }
}

static GtkWidget *proton_linux_menu_create_action_item(
    const char *label,
    const char *value,
    const char *key,
    int is_command,
    GdkModifierType extra_modifiers,
    GtkAccelGroup *accelerators,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data) {
  GtkWidget *item = gtk_menu_item_new_with_label(label);
  if (item == NULL ||
      !proton_linux_menu_bind_activation(
          item, value, is_command, command_callback, role_callback,
          user_data)) {
    if (item != NULL) {
      gtk_widget_destroy(item);
    }
    return NULL;
  }
  proton_linux_menu_add_accelerator(item, accelerators, key,
                                    extra_modifiers);
  return item;
}

static int proton_linux_menu_append_role(
    GtkWidget *menu,
    const char *role,
    const char *label,
    const char *key,
    GtkAccelGroup *accelerators,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data) {
  GtkWidget *item = proton_linux_menu_create_action_item(
      label, role, key != NULL ? key : "", 0,
      strcmp(role, "hide_others") == 0 ? GDK_MOD1_MASK : 0, accelerators,
      command_callback, role_callback, user_data);
  if (item == NULL) {
    return 0;
  }
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  return 1;
}

static GtkWidget *proton_linux_menu_create_custom_menu(
    const proton_linux_menu_t *definition,
    GtkAccelGroup *accelerators,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data) {
  GtkWidget *menu = gtk_menu_new();
  if (menu == NULL) {
    return NULL;
  }
  for (size_t index = 0; index < definition->item_count; index++) {
    const proton_linux_menu_item_t *definition_item =
        &definition->items[index];
    GtkWidget *item = NULL;
    if (definition_item->kind == PROTON_LINUX_MENU_ITEM_SEPARATOR) {
      item = gtk_separator_menu_item_new();
    } else if (definition_item->kind == PROTON_LINUX_MENU_ITEM_COMMAND) {
      item = proton_linux_menu_create_action_item(
          definition_item->label, definition_item->id, definition_item->key,
          1, 0, accelerators, command_callback, role_callback, user_data);
    } else if (!proton_linux_menu_append_role(
                   menu, definition_item->role, definition_item->label,
                   definition_item->key, accelerators,
                   command_callback, role_callback, user_data)) {
      gtk_widget_destroy(menu);
      return NULL;
    } else {
      continue;
    }
    if (item == NULL) {
      gtk_widget_destroy(menu);
      return NULL;
    }
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  }
  return menu;
}

static int proton_linux_menu_append_top_level(GtkWidget *menu_bar,
                                              const char *label,
                                              GtkWidget *menu) {
  GtkWidget *item = gtk_menu_item_new_with_label(label);
  if (item == NULL) {
    gtk_widget_destroy(menu);
    return 0;
  }
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), menu);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_bar), item);
  return 1;
}

GtkWidget *proton_linux_menu_bar_create_widget(
    const proton_linux_menu_bar_t *menu_bar,
    GtkAccelGroup *accelerators,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data,
    char *error,
    size_t error_len) {
  if (menu_bar == NULL || command_callback == NULL || role_callback == NULL) {
    proton_linux_menu_set_message(error, error_len,
                                  "menu widget callbacks are required");
    return NULL;
  }
  GtkWidget *widget = gtk_menu_bar_new();
  if (widget == NULL) {
    proton_linux_menu_set_message(error, error_len,
                                  "failed to create menu bar widget");
    return NULL;
  }

  for (size_t index = 0; index < menu_bar->menu_count; index++) {
    const proton_linux_menu_t *definition = &menu_bar->menus[index];
    GtkWidget *menu = proton_linux_menu_create_custom_menu(
        definition, accelerators, command_callback, role_callback, user_data);
    if (menu == NULL || !proton_linux_menu_append_top_level(
                            widget, definition->label, menu)) {
      gtk_widget_destroy(widget);
      proton_linux_menu_set_message(error, error_len,
                                    "failed to create custom menu");
      return NULL;
    }
  }

  return widget;
}
