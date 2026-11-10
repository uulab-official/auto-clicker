/* Test-only interposer. It inserts a Carbon hotkey event into this process's
 * own queue after the isolated test asks it to. It does not emulate hardware
 * and must never be included in a release build. */
#include <Carbon/Carbon.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static EventHotKeyID observed;

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
        if (access(signal, F_OK) == 0) {
            dispatch_async_f(dispatch_get_main_queue(), NULL, post_hotkey);
            return NULL;
        }
        usleep(100000);
    }
    fprintf(stderr, "queue-test: timed out awaiting signal\n");
    return NULL;
}
__attribute__((constructor)) static void initialize(void) {
    if (!getenv("AUTOCLICKER_QUEUE_TEST_SIGNAL")) return;
    const char *id = getenv("AUTOCLICKER_QUEUE_TEST_ID");
    if (!id) { fprintf(stderr, "queue-test: missing shortcut id\n"); return; }
    observed.id = (UInt32)strtoul(id, NULL, 10);
    observed.signature = 0x68747273; /* global-hotkey's Carbon signature: htrs */
    fprintf(stderr, "queue-test: prepared shortcut id=%u\n", observed.id);
    pthread_t thread;
    if (pthread_create(&thread, NULL, wait_for_test, NULL) == 0) pthread_detach(thread);
}
