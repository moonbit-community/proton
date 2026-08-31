#ifndef PROTON_ENGINE_CEF_MAC_DIALOG_H
#define PROTON_ENGINE_CEF_MAC_DIALOG_H

#include <stdint.h>

void proton_engine_dialog_complete_window_closed(uint64_t native_id);
void proton_engine_dialog_dispose_runtime(void *runtime);

#endif
