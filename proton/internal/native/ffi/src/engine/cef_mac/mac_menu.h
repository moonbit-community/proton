#ifndef PROTON_ENGINE_CEF_MAC_MENU_H
#define PROTON_ENGINE_CEF_MAC_MENU_H

#include "../../proton_engine.h"

#include <stddef.h>
#include <stdint.h>

void proton_engine_menu_install_default(void);
void proton_engine_menu_set_runtime(proton_engine_runtime_t *runtime);
void proton_engine_menu_clear_runtime(proton_engine_runtime_t *runtime);
int32_t proton_engine_menu_set_on_main(const proton_menu_bar_t *menu_bar,
                                       char *error, size_t error_len);

#endif
