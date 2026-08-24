#if defined(__linux__)

#include "proton_linux_menu.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef proton_menu_item_t proton_linux_menu_item_t;
typedef proton_menu_t proton_linux_menu_t;

#define PROTON_LINUX_MENU_ITEM_COMMAND PROTON_MENU_ITEM_COMMAND
#define PROTON_LINUX_MENU_ITEM_SEPARATOR PROTON_MENU_ITEM_SEPARATOR
#define PROTON_LINUX_MENU_ITEM_ROLE PROTON_MENU_ITEM_ROLE

typedef struct {
  proton_linux_menu_command_callback_t command_callback;
  proton_linux_menu_role_callback_t role_callback;
  void *user_data;
  char *value;
  int is_command;
} proton_linux_menu_activation_t;

static void proton_linux_menu_set_message(char *error,
                                          size_t error_len,
                                          const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

void proton_linux_menu_bar_destroy(proton_linux_menu_bar_t *menu_bar) {
  proton_menu_bar_destroy(menu_bar);
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

#endif
