/* Availability probe only: never emits keyboard reports. The test workflow
 * invokes it only on a disposable GitHub-hosted VM. */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDUserDevice.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    if (!getenv("GITHUB_ACTIONS") || strcmp(getenv("GITHUB_ACTIONS"), "true") ||
        !getenv("RUNNER_ENVIRONMENT") || strcmp(getenv("RUNNER_ENVIRONMENT"), "github-hosted")) {
        fprintf(stderr, "Disposable GitHub runner required\n"); return 2;
    }
    const UInt8 report[] = {
        0x05,0x01,0x09,0x06,0xa1,0x01,0x05,0x07,0x19,0xe0,0x29,0xe7,
        0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x08,0x81,0x02,0x95,0x01,
        0x75,0x08,0x81,0x01,0x95,0x06,0x75,0x08,0x15,0x00,0x25,0x65,
        0x05,0x07,0x19,0x00,0x29,0x65,0x81,0x00,0xc0
    };
    CFDataRef data = CFDataCreate(NULL, report, sizeof(report));
    const void *keys[] = { CFSTR(kIOHIDReportDescriptorKey) };
    const void *values[] = { data };
    CFDictionaryRef props = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDUserDeviceRef device = IOHIDUserDeviceCreateWithProperties(NULL, props, 0);
    if (device) {
        printf("Virtual HID device creation succeeded; no keyboard report was sent\n");
        CFRelease(device);
    } else {
        printf("Virtual HID device unavailable in this runner without its required entitlement\n");
    }
    CFRelease(props);
    CFRelease(data);
    return 0;
}
