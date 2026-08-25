#if defined(__linux__)

#include "linux_internal.h"

#include "../../proton_event.h"
#include "../cef_common/message.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef proton_menu_item_t proton_linux_menu_item_t;
typedef proton_menu_t proton_linux_menu_t;

#define PROTON_LINUX_MENU_ITEM_COMMAND PROTON_MENU_ITEM_COMMAND
#define PROTON_LINUX_MENU_ITEM_SEPARATOR PROTON_MENU_ITEM_SEPARATOR
#define PROTON_LINUX_MENU_ITEM_ROLE PROTON_MENU_ITEM_ROLE
#define PROTON_LINUX_MENU_ITEM_SUBMENU PROTON_MENU_ITEM_SUBMENU

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
    void *user_data);

static int proton_linux_menu_append_submenu(
    GtkWidget *menu,
    const proton_menu_item_t *definition_item,
    GtkAccelGroup *accelerators,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data) {
  if (definition_item->label == NULL ||
      definition_item->submenu == NULL) {
    return 0;
  }
  GtkWidget *submenu = proton_linux_menu_create_custom_menu(
      definition_item->submenu, accelerators, command_callback,
      role_callback, user_data);
  if (submenu == NULL) {
    return 0;
  }
  GtkWidget *item = gtk_menu_item_new_with_label(definition_item->label);
  if (item == NULL) {
    gtk_widget_destroy(submenu);
    return 0;
  }
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), submenu);
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
    if (definition_item->kind == PROTON_LINUX_MENU_ITEM_SUBMENU) {
      if (!proton_linux_menu_append_submenu(
              menu, definition_item, accelerators, command_callback,
              role_callback, user_data)) {
        gtk_widget_destroy(menu);
        return NULL;
      }
      continue;
    }
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

GtkWidget *proton_linux_menu_create_popup_widget(
    const proton_linux_menu_bar_t *menu_bar,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data,
    char *error,
    size_t error_len) {
  if (menu_bar == NULL || menu_bar->menu_count == 0 ||
      command_callback == NULL || role_callback == NULL) {
    proton_linux_menu_set_message(error, error_len,
                                  "popup widget requires a menu definition");
    return NULL;
  }
  /* A context menu has a single top-level definition whose items are shown
     directly. Accelerators are not needed for a transient popup. */
  return proton_linux_menu_create_custom_menu(
      &menu_bar->menus[0], NULL, command_callback, role_callback, user_data);
}

static void proton_engine_menu_enqueue_command(
    proton_engine_runtime_t *runtime,
    const char *command_id,
    proton_window_id_t focused_window) {
  if (runtime == NULL || command_id == NULL) {
    return;
  }
  proton_event_t *event = proton_event_create(PROTON_EVENT_MENU_COMMAND);
  if (event == NULL ||
      !proton_event_set_text(&event->text_a, command_id)) {
    proton_event_destroy(event);
    return;
  }
  event->window = focused_window;
  (void)proton_event_publish(event);
}

static void proton_engine_menu_command_activated(const char *command_id,
                                                 void *user_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || window->runtime == NULL) {
    return;
  }
  proton_engine_menu_enqueue_command(window->runtime, command_id,
                                     window->public_window_id);
}

static void proton_engine_menu_apply_edit_role(
    proton_engine_window_t *window,
    const char *role) {
  if (window == NULL || window->browser == NULL || role == NULL) {
    return;
  }
  cef_frame_t *frame =
      window->browser->get_focused_frame != NULL
          ? window->browser->get_focused_frame(window->browser)
          : NULL;
  if (frame == NULL) {
    frame = window->browser->get_main_frame(window->browser);
  }
  if (frame == NULL) {
    return;
  }
  if (strcmp(role, "undo") == 0) {
    frame->undo(frame);
  } else if (strcmp(role, "redo") == 0) {
    frame->redo(frame);
  } else if (strcmp(role, "cut") == 0) {
    frame->cut(frame);
  } else if (strcmp(role, "copy") == 0) {
    frame->copy(frame);
  } else if (strcmp(role, "paste") == 0) {
    frame->paste(frame);
  } else if (strcmp(role, "select_all") == 0) {
    frame->select_all(frame);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void proton_engine_menu_role_activated(const char *role,
                                              void *user_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || window->runtime == NULL || role == NULL) {
    return;
  }
  if (strcmp(role, "quit") == 0) {
    for (proton_engine_window_t *candidate = proton_engine_windows_head();
         candidate != NULL;
         candidate = candidate->next) {
      if (candidate->runtime == window->runtime &&
          candidate->window != NULL) {
        gtk_window_close(GTK_WINDOW(candidate->window));
      }
    }
  } else if (strcmp(role, "hide") == 0) {
    if (window->window != NULL) {
      gtk_widget_hide(window->window);
    }
  } else if (strcmp(role, "hide_others") == 0) {
    for (proton_engine_window_t *candidate = proton_engine_windows_head();
         candidate != NULL;
         candidate = candidate->next) {
      if (candidate != window && candidate->runtime == window->runtime &&
          candidate->window != NULL) {
        gtk_widget_hide(candidate->window);
      }
    }
  } else if (strcmp(role, "show_all") == 0) {
    for (proton_engine_window_t *candidate = proton_engine_windows_head();
         candidate != NULL;
         candidate = candidate->next) {
      if (candidate->runtime == window->runtime &&
          candidate->window != NULL) {
        gtk_widget_show_all(candidate->window);
      }
    }
  } else if (strcmp(role, "close") == 0) {
    if (window->window != NULL) {
      gtk_window_close(GTK_WINDOW(window->window));
    }
  } else if (strcmp(role, "minimize") == 0) {
    if (window->window != NULL) {
      gtk_window_iconify(GTK_WINDOW(window->window));
    }
  } else if (strcmp(role, "zoom") == 0) {
    proton_engine_overlay_toggle_maximize(window);
  } else {
    proton_engine_menu_apply_edit_role(window, role);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

int32_t proton_engine_window_install_menu(
    proton_engine_window_t *window,
    const proton_linux_menu_bar_t *menu_definition,
    char *error,
    size_t error_len) {
  if (window == NULL || window->window == NULL || window->root_box == NULL ||
      menu_definition == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and menu definition are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  GtkAccelGroup *accelerators = gtk_accel_group_new();
  if (accelerators == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create menu accelerators");
    return PROTON_ERR_PLATFORM;
  }
  GtkWidget *menu_bar = proton_linux_menu_bar_create_widget(
      menu_definition, accelerators, proton_engine_menu_command_activated,
      proton_engine_menu_role_activated, window, error, error_len);
  if (menu_bar == NULL) {
    g_object_unref(accelerators);
    return PROTON_ERR_PLATFORM;
  }

  if (window->menu_accel_group != NULL) {
    gtk_window_remove_accel_group(GTK_WINDOW(window->window),
                                  window->menu_accel_group);
    g_object_unref(window->menu_accel_group);
  }
  if (window->menu_bar != NULL) {
    gtk_widget_destroy(window->menu_bar);
  }
  window->menu_bar = menu_bar;
  window->menu_accel_group = accelerators;
  gtk_window_add_accel_group(GTK_WINDOW(window->window), accelerators);
  gtk_box_pack_start(GTK_BOX(window->root_box), menu_bar, FALSE, FALSE, 0);
  gtk_box_reorder_child(GTK_BOX(window->root_box), menu_bar, 0);
  gtk_widget_show_all(menu_bar);
  proton_engine_sync_browser_bounds(window);
  return PROTON_OK;
}

int32_t proton_engine_runtime_set_menu(
    proton_engine_runtime_t *runtime, const proton_menu_bar_t *menu_bar,
    char *error, size_t error_len) {
  if (runtime == NULL || !proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (runtime->headless) {
    proton_engine_set_message(error, error_len,
                              "native menus are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  proton_linux_menu_bar_t *menu_definition = proton_menu_bar_clone(menu_bar);
  if (menu_definition == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to copy menu definition");
    return PROTON_ERR_ENGINE;
  }
  for (proton_engine_window_t *window = proton_engine_windows_head();
       window != NULL;
       window = window->next) {
    if (window->runtime != runtime || window->window == NULL) {
      continue;
    }
    const int32_t status = proton_engine_window_install_menu(
        window, menu_definition, error, error_len);
    if (status != PROTON_OK) {
      proton_linux_menu_bar_destroy(menu_definition);
      return status;
    }
  }
  proton_linux_menu_bar_destroy(runtime->menu_definition);
  runtime->menu_definition = menu_definition;
  return PROTON_OK;
}

int32_t proton_engine_window_popup_menu(
    proton_engine_window_t *window, int32_t x, int32_t y,
    const proton_menu_bar_t *menu_bar, char *error, size_t error_len) {
  if (window == NULL || !proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (menu_bar == NULL || menu_bar->menu_count == 0) {
    proton_engine_set_message(error, error_len,
                              "popup menu requires at least one menu");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->window == NULL || window->browser_host == NULL ||
      gtk_widget_get_window(window->browser_host) == NULL) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for a popup menu");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  GtkWidget *popup = proton_linux_menu_create_popup_widget(
      menu_bar, proton_engine_menu_command_activated,
      proton_engine_menu_role_activated, window, error, error_len);
  if (popup == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create popup menu");
    return PROTON_ERR_PLATFORM;
  }
  gtk_widget_show_all(popup);
  /* Renderer coordinates use the browser host's top-left CSS-pixel space.
     GTK 3 popup rectangles use GDK logical coordinates, which match that
     space without applying the monitor scale factor again. */
  GdkRectangle anchor = {
      .x = x,
      .y = y,
      .width = 1,
      .height = 1,
  };
  gtk_menu_popup_at_rect(GTK_MENU(popup),
                         gtk_widget_get_window(window->browser_host), &anchor,
                         GDK_GRAVITY_NORTH_WEST, GDK_GRAVITY_NORTH_WEST, NULL);
  return PROTON_OK;
}

#endif
