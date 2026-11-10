/* Synthetic HIDSystem events on disposable hosted macOS runners only.
 * This is not a hardware keyboard and is not part of the application. */
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>
#include <IOKit/hidsystem/IOLLEvent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static kern_return_t post(io_connect_t conn, UInt32 type, UInt16 code, IOOptionBits flags) {
    NXEventData event = {0};
    event.key.keyCode = code;
    IOGPoint point = {0, 0};
    kern_return_t result = IOHIDPostEvent(conn, type, point, &event, kNXEventDataVersion,
                                          flags, kIOHIDSetGlobalEventFlags);
    fprintf(stderr, "IOHIDPostEvent type=%u code=%u result=0x%x\n", type, code, result);
    usleep(100000);
    return result;
}

int main(int argc, char **argv) {
    const char *gh = getenv("GITHUB_ACTIONS"), *ci = getenv("CI"), *hosted = getenv("RUNNER_ENVIRONMENT");
    if (!gh || strcmp(gh, "true") || !ci || strcmp(ci, "true") || !hosted || strcmp(hosted, "github-hosted")) {
        fprintf(stderr, "Disposable GitHub-hosted runner required\n"); return 2;
    }
    if (argc != 2 || (strcmp(argv[1], "F7") && strcmp(argv[1], "F8") && strcmp(argv[1], "Escape"))) {
        fprintf(stderr, "Expected F7, F8 or Escape\n"); return 2;
    }
    UInt16 key = !strcmp(argv[1], "F7") ? 98 : !strcmp(argv[1], "F8") ? 100 : 53;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!service) { fprintf(stderr, "HIDSystem unavailable\n"); return 3; }
    io_connect_t conn = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) { fprintf(stderr, "IOServiceOpen failed: 0x%x\n", kr); return 3; }
    const IOOptionBits ctrl = NX_CONTROLMASK | NX_DEVICELCTLKEYMASK;
    const IOOptionBits both = ctrl | NX_SHIFTMASK | NX_DEVICELSHIFTKEYMASK;
    int failed = 0;
    failed |= post(conn, NX_FLAGSCHANGED, 59, ctrl) != KERN_SUCCESS;
    failed |= post(conn, NX_FLAGSCHANGED, 56, both) != KERN_SUCCESS;
    failed |= post(conn, NX_KEYDOWN, key, both) != KERN_SUCCESS;
    failed |= post(conn, NX_KEYUP, key, both) != KERN_SUCCESS;
    /* Always release modifiers, including on failure. */
    failed |= post(conn, NX_FLAGSCHANGED, 56, ctrl) != KERN_SUCCESS;
    failed |= post(conn, NX_FLAGSCHANGED, 59, 0) != KERN_SUCCESS;
    IOServiceClose(conn);
    return failed ? 1 : 0;
}
