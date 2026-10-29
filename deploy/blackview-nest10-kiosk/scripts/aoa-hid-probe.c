#include <libusb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define AOA_GET_PROTOCOL 51
#define AOA_SEND_STRING 52
#define AOA_START 53
#define AOA_REGISTER_HID 54
#define AOA_UNREGISTER_HID 55
#define AOA_SET_HID_REPORT_DESC 56
#define AOA_SEND_HID_EVENT 57

#define NEST_VENDOR 0x18d1
#define NEST_PRODUCT 0x0007
#define ACCESSORY_PRODUCT 0x2d00
#define HID_ID 1

static const unsigned char consumer_descriptor[] = {
    0x05, 0x0c,       /* Usage Page (Consumer) */
    0x09, 0x01,       /* Usage (Consumer Control) */
    0xa1, 0x01,       /* Collection (Application) */
    0x15, 0x00,       /* Logical Minimum (0) */
    0x26, 0xff, 0x03, /* Logical Maximum (1023) */
    0x19, 0x00,       /* Usage Minimum (0) */
    0x2a, 0xff, 0x03, /* Usage Maximum (1023) */
    0x75, 0x10,       /* Report Size (16) */
    0x95, 0x01,       /* Report Count (1) */
    0x81, 0x00,       /* Input (Data, Array, Absolute) */
    0xc0              /* End Collection */
};

static const unsigned char keyboard_descriptor[] = {
    0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0x05, 0x07,
    0x19, 0xe0, 0x29, 0xe7, 0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01,
    0x75, 0x08, 0x81, 0x01, 0x95, 0x06, 0x75, 0x08,
    0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00,
    0x29, 0x65, 0x81, 0x00, 0xc0
};

static void fail(const char *message, int code) {
    fprintf(stderr, "%s: %s\n", message, libusb_error_name(code));
    exit(1);
}

static libusb_device_handle *open_device(uint16_t product) {
    return libusb_open_device_with_vid_pid(NULL, NEST_VENDOR, product);
}

static void send_string(libusb_device_handle *device, uint16_t index,
                        const char *value) {
    int result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_SEND_STRING, 0, index, (unsigned char *)value,
        (uint16_t)(strlen(value) + 1), 1000);
    if (result < 0) fail("AOA identification failed", result);
}

static libusb_device_handle *enter_accessory_mode(void) {
    libusb_device_handle *device = open_device(NEST_PRODUCT);
    if (!device) return open_device(ACCESSORY_PRODUCT);

    unsigned char protocol[2] = {0};
    int result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_GET_PROTOCOL, 0, 0, protocol, sizeof(protocol), 1000);
    if (result < 0) fail("AOA protocol query failed", result);
    printf("AOA protocol %u detected. Switching to accessory mode...\n",
           (unsigned)(protocol[0] | (protocol[1] << 8)));

    send_string(device, 0, "CASE");
    send_string(device, 1, "NEST 10 launcher probe");
    send_string(device, 2, "Non-persistent Android launch-key probe");
    send_string(device, 3, "1.0");
    send_string(device, 4, "https://case.local/");
    send_string(device, 5, "case-nest10-hid-probe");

    result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_START, 0, 0, NULL, 0, 1000);
    if (result < 0) fail("AOA start failed", result);
    libusb_close(device);

    for (int attempt = 0; attempt < 50; attempt++) {
        usleep(200000);
        device = open_device(ACCESSORY_PRODUCT);
        if (device) return device;
    }
    fprintf(stderr, "NEST did not re-enumerate in accessory mode.\n");
    exit(1);
}

static void register_hid(libusb_device_handle *device,
                         const unsigned char *descriptor,
                         uint16_t descriptor_size) {
    int result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_REGISTER_HID, HID_ID, descriptor_size, NULL, 0, 1000);
    if (result < 0) fail("AOA HID registration failed", result);

    result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_SET_HID_REPORT_DESC, HID_ID, 0,
        (unsigned char *)descriptor, descriptor_size, 1000);
    if (result < 0) fail("AOA HID descriptor upload failed", result);
    usleep(500000);
}

static void send_keyboard(libusb_device_handle *device, uint8_t modifier,
                          uint8_t key) {
    unsigned char report[8] = {modifier, 0, key, 0, 0, 0, 0, 0};
    unsigned char release[8] = {0};
    int result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_SEND_HID_EVENT, HID_ID, 0, report, sizeof(report), 1000);
    if (result < 0) fail("AOA keyboard event failed", result);
    usleep(100000);
    result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_SEND_HID_EVENT, HID_ID, 0, release, sizeof(release), 1000);
    if (result < 0) fail("AOA keyboard release failed", result);
}

static void send_usage(libusb_device_handle *device, uint16_t usage) {
    unsigned char report[2] = {(unsigned char)(usage & 0xff),
                               (unsigned char)(usage >> 8)};
    unsigned char release[2] = {0, 0};
    int result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_SEND_HID_EVENT, HID_ID, 0, report, sizeof(report), 1000);
    if (result < 0) fail("AOA HID event failed", result);
    usleep(80000);
    result = libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_SEND_HID_EVENT, HID_ID, 0, release, sizeof(release), 1000);
    if (result < 0) fail("AOA HID release failed", result);
}

int main(int argc, char **argv) {
    int keyboard_mode = argc == 4 && strcmp(argv[1], "--key") == 0;
    if (argc != 2 && !keyboard_mode) {
        fprintf(stderr,
                "Usage: %s <consumer-usage-hex>\n"
                "       %s --key <modifier-hex> <key-usage-hex>\n",
                argv[0], argv[0]);
        return 2;
    }

    char *end = NULL;
    unsigned long parsed = strtoul(keyboard_mode ? argv[2] : argv[1], &end, 0);
    unsigned long key = 0;
    if (!end || *end != '\0' || parsed > (keyboard_mode ? 0xff : 0x03ff)) {
        fprintf(stderr, "Invalid HID value.\n");
        return 2;
    }
    if (keyboard_mode) {
        end = NULL;
        key = strtoul(argv[3], &end, 0);
        if (!end || *end != '\0' || key > 0xff) {
            fprintf(stderr, "Invalid keyboard usage.\n");
            return 2;
        }
    }

    int result = libusb_init(NULL);
    if (result < 0) fail("libusb initialization failed", result);
    libusb_device_handle *device = enter_accessory_mode();
    if (!device) {
        fprintf(stderr, "NEST 10 USB device not found.\n");
        libusb_exit(NULL);
        return 1;
    }

    if (keyboard_mode) {
        register_hid(device, keyboard_descriptor, sizeof(keyboard_descriptor));
        printf("Sending keyboard modifier 0x%02lx + usage 0x%02lx...\n",
               parsed, key);
        send_keyboard(device, (uint8_t)parsed, (uint8_t)key);
    } else {
        register_hid(device, consumer_descriptor, sizeof(consumer_descriptor));
        printf("Sending consumer usage 0x%04lx...\n", parsed);
        send_usage(device, (uint16_t)parsed);
    }
    usleep(200000);
    libusb_control_transfer(
        device, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR,
        AOA_UNREGISTER_HID, HID_ID, 0, NULL, 0, 1000);
    libusb_close(device);
    libusb_exit(NULL);
    return 0;
}
