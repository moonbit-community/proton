#ifndef PROTON_ENGINE_CEF_MAC_DIALOG_H
#define PROTON_ENGINE_CEF_MAC_DIALOG_H

#include <stdint.h>

typedef void (*proton_engine_dialog_signal_callback_t)(uint32_t ready_mask);

void proton_engine_dialog_set_signal_callback(
    proton_engine_dialog_signal_callback_t callback);
void proton_engine_dialog_complete_window_closed(uint64_t native_id);

#endif
