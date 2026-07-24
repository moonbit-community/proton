#ifndef PROTON_ENGINE_CEF_MAC_MENU_H
#define PROTON_ENGINE_CEF_MAC_MENU_H

#include "../../proton_engine.h"

#include <stddef.h>
#include <stdint.h>

typedef void (*proton_engine_menu_signal_callback_t)(uint32_t ready_mask);

void proton_engine_menu_set_signal_callback(
    proton_engine_menu_signal_callback_t callback);
void proton_engine_menu_install_default(void);
void proton_engine_menu_set_runtime(proton_engine_runtime_t *runtime);
void proton_engine_menu_clear_runtime(proton_engine_runtime_t *runtime);
int32_t proton_engine_menu_set_json_on_main(const char *menu_json,
                                            char *error,
                                            size_t error_len);

#endif
