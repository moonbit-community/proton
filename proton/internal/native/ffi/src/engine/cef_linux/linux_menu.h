#ifndef PROTON_LINUX_MENU_H
#define PROTON_LINUX_MENU_H

#include "../../proton_menu.h"

#include <gtk/gtk.h>

#include <stddef.h>

typedef proton_menu_bar_t proton_linux_menu_bar_t;

typedef void (*proton_linux_menu_command_callback_t)(const char *command_id,
                                                     void *user_data);
typedef void (*proton_linux_menu_role_callback_t)(const char *role,
                                                  void *user_data);

void proton_linux_menu_bar_destroy(proton_linux_menu_bar_t *menu_bar);

GtkWidget *proton_linux_menu_bar_create_widget(
    const proton_linux_menu_bar_t *menu_bar,
    GtkAccelGroup *accelerators,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data,
    char *error,
    size_t error_len);

GtkWidget *proton_linux_menu_create_popup_widget(
    const proton_linux_menu_bar_t *menu_bar,
    proton_linux_menu_command_callback_t command_callback,
    proton_linux_menu_role_callback_t role_callback,
    void *user_data,
    char *error,
    size_t error_len);

#endif
