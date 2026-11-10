/* Test-only interposer. It inserts a Carbon hotkey event into this process's
 * own queue after the isolated test asks it to. It does not emulate hardware
 * and must never be included in a release build. */
#include <Carbon/Carbon.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static EventHotKeyID observed;
static int registered;
static OSStatus capture_register(UInt32 code, UInt32 mods, EventHotKeyID ident,
                                 EventTargetRef target, OptionBits options,
                                 EventHotKeyRef *result) {
    typedef OSStatus (*register_fn)(UInt32, UInt32, EventHotKeyID, EventTargetRef, OptionBits, EventHotKeyRef *);
    register_fn real = (register_fn)dlsym(RTLD_NEXT, "RegisterEventHotKey");
    if (!real) return -1;
    OSStatus status = real(code, mods, ident, target, options, result);
    if (status == noErr && code == 100 && mods == (controlKey | shiftKey)) {
        observed = ident;
        __atomic_store_n(&registered, 1, __ATOMIC_RELEASE);
        fprintf(stderr, "queue-test: observed F8 registration id=%u\n", ident.id);
    }
    return status;
}
__attribute__((used)) static const struct { const void *replacement; const void *original; } interpose
    __attribute__((section("__DATA,__interpose"))) = {(const void *)capture_register, (const void *)RegisterEventHotKey};

static void post_hotkey(void *unused) {
    (void)unused;
    EventRef event = NULL;
    OSStatus a = CreateEvent(NULL, kEventClassKeyboard, kEventHotKeyPressed,
                             GetCurrentEventTime(), kEventAttributeUserEvent, &event);
    OSStatus b = a == noErr ? SetEventParameter(event, kEventParamDirectObject,
                         typeEventHotKeyID, sizeof(observed), &observed) : a;
    OSStatus c = b == noErr ? PostEventToQueue(GetMainEventQueue(), event, kEventPriorityHigh) : b;
    if (event) ReleaseEvent(event);
    fprintf(stderr, "queue-test: posted in-process Carbon hotkey event status=%d/%d/%d\n", (int)a, (int)b, (int)c);
}

static void *wait_for_test(void *unused) {
    (void)unused;
    const char *signal = getenv("AUTOCLICKER_QUEUE_TEST_SIGNAL");
    if (!signal) return NULL;
    for (int i = 0; i < 1200; ++i) {
        if (__atomic_load_n(&registered, __ATOMIC_ACQUIRE) && access(signal, F_OK) == 0) {
            dispatch_async_f(dispatch_get_main_queue(), NULL, post_hotkey);
            return NULL;
        }
        usleep(100000);
    }
    fprintf(stderr, "queue-test: timed out awaiting registration or signal\n");
    return NULL;
}
__attribute__((constructor)) static void initialize(void) {
    if (!getenv("AUTOCLICKER_QUEUE_TEST_SIGNAL")) return;
    pthread_t thread;
    if (pthread_create(&thread, NULL, wait_for_test, NULL) == 0) pthread_detach(thread);
}
