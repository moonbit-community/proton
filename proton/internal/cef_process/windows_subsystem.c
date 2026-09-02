#include <moonbit.h>

#if defined(_WIN32)
/* CEF launches this executable once per subprocess. Keep MoonBit's regular
   main entry point without allocating a console for every child process. */
#pragma comment(linker, "/SUBSYSTEM:WINDOWS")
#pragma comment(linker, "/ENTRY:mainCRTStartup")
#endif

MOONBIT_FFI_EXPORT void proton_cef_process_link_anchor(void) {}
