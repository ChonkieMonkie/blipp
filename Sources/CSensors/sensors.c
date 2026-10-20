// Blipp, a menu bar sidekick that shows how your Mac is doing.
// Copyright (C) 2026  Anton Gedda
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#include "CSensors.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Apple Silicon exposes its temperature sensors through the IOHIDEventSystem.
// These functions live in IOKit but are not part of the public headers.
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kBlippEventTypeTemperature 15
#define kBlippTemperatureField (kBlippEventTypeTemperature << 16)

static IOHIDEventSystemClientRef sClient = NULL;
static CFArrayRef sServices = NULL;      // every temperature sensor
static CFMutableArrayRef sDieSensors = NULL;  // just the CPU die sensors, found once

static int blipp_is_die_sensor(CFTypeRef name) {
    if (name == NULL || CFGetTypeID(name) != CFStringGetTypeID()) {
        return 0;
    }
    char buffer[128];
    if (!CFStringGetCString((CFStringRef)name, buffer, sizeof buffer, kCFStringEncodingUTF8)) {
        return 0;
    }
    return strstr(buffer, "tdie") != NULL || strstr(buffer, "pACC") != NULL || strstr(buffer, "eACC") != NULL;
}

static void blipp_setup(void) {
    if (sClient != NULL) {
        return;
    }
    sClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (sClient == NULL) {
        return;
    }

    int page = 0xff00;  // Apple vendor usage page
    int usage = 5;      // temperature sensor
    CFNumberRef pageRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usageRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {pageRef, usageRef};
    CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
                                                  &kCFTypeDictionaryKeyCallBacks,
                                                  &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(sClient, matching);
    CFRelease(matching);
    CFRelease(pageRef);
    CFRelease(usageRef);

    sServices = IOHIDEventSystemClientCopyServices(sClient);
    if (sServices == NULL) {
        return;
    }

    // Reading a sensor costs a round trip to the kernel, so remember which ones matter
    // and only ever read those.
    sDieSensors = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFIndex count = CFArrayGetCount(sServices);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(sServices, i);
        CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (blipp_is_die_sensor(name)) {
            CFArrayAppendValue(sDieSensors, service);
        }
        if (name != NULL) {
            CFRelease(name);
        }
    }
}

static double blipp_read(IOHIDServiceClientRef service) {
    IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kBlippEventTypeTemperature, 0, 0);
    if (event == NULL) {
        return -1;
    }
    double value = IOHIDEventGetFloatValue(event, kBlippTemperatureField);
    CFRelease(event);
    return (value > 0 && value < 150) ? value : -1;
}

// The SMC's CPU core sensors (keys "Tp…" for performance cores, "Te…" for efficiency
// cores) sit right on the cores. The HID die sensors above are spread over the whole
// chip and read 20 °C or more below the cores under load, so the SMC is preferred.
typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} BlippSMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuLimit, gpuLimit, memoryLimit;
} BlippSMCLimits;

typedef struct {
    uint32_t dataSize, dataType;
    uint8_t dataAttributes;
} BlippSMCKeyInfo;

typedef struct {
    uint32_t key;
    BlippSMCVersion version;
    BlippSMCLimits limits;
    BlippSMCKeyInfo keyInfo;
    uint8_t result, status, command;
    uint32_t data32;
    uint8_t bytes[32];
} BlippSMCParams;

enum { kBlippSMCReadBytes = 5, kBlippSMCReadIndex = 8, kBlippSMCReadKeyInfo = 9 };

typedef struct {
    uint32_t key;
    BlippSMCKeyInfo info;
} BlippSMCSensor;

static io_connect_t sSMC = 0;
static BlippSMCSensor *sCoreSensors = NULL;
static CFIndex sCoreCount = 0;

static uint32_t blipp_fourcc(const char *code) {
    return ((uint32_t)code[0] << 24) | ((uint32_t)code[1] << 16) | ((uint32_t)code[2] << 8) | (uint32_t)code[3];
}

static int blipp_smc_call(BlippSMCParams *input, BlippSMCParams *output) {
    size_t size = sizeof *output;
    kern_return_t result = IOConnectCallStructMethod(sSMC, 2, input, sizeof *input, output, &size);
    return result == KERN_SUCCESS && output->result == 0;
}

static void blipp_smc_setup(void) {
    static int done = 0;
    if (done) {
        return;
    }
    done = 1;

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return;
    }
    kern_return_t opened = IOServiceOpen(service, mach_task_self(), 0, &sSMC);
    IOObjectRelease(service);
    if (opened != KERN_SUCCESS) {
        sSMC = 0;
        return;
    }

    // Walk the SMC's key list once and keep the float core sensors.
    BlippSMCParams input = {0}, output = {0};
    input.key = blipp_fourcc("#KEY");
    input.command = kBlippSMCReadKeyInfo;
    if (!blipp_smc_call(&input, &output)) {
        return;
    }
    input.keyInfo = output.keyInfo;
    input.command = kBlippSMCReadBytes;
    if (!blipp_smc_call(&input, &output)) {
        return;
    }
    uint32_t keyCount = ((uint32_t)output.bytes[0] << 24) | ((uint32_t)output.bytes[1] << 16) |
                        ((uint32_t)output.bytes[2] << 8) | (uint32_t)output.bytes[3];

    CFIndex capacity = 0;
    for (uint32_t index = 0; index < keyCount; index++) {
        memset(&input, 0, sizeof input);
        input.command = kBlippSMCReadIndex;
        input.data32 = index;
        if (!blipp_smc_call(&input, &output)) {
            continue;
        }
        uint32_t key = output.key;
        char first = (char)(key >> 24), second = (char)(key >> 16);
        if (first != 'T' || (second != 'p' && second != 'e')) {
            continue;
        }

        memset(&input, 0, sizeof input);
        input.key = key;
        input.command = kBlippSMCReadKeyInfo;
        if (!blipp_smc_call(&input, &output) || output.keyInfo.dataType != blipp_fourcc("flt ") ||
            output.keyInfo.dataSize != 4) {
            continue;
        }

        if (sCoreCount == capacity) {
            capacity = capacity == 0 ? 32 : capacity * 2;
            BlippSMCSensor *grown = realloc(sCoreSensors, (size_t)capacity * sizeof *grown);
            if (grown == NULL) {
                break;
            }
            sCoreSensors = grown;
        }
        sCoreSensors[sCoreCount++] = (BlippSMCSensor){key, output.keyInfo};
    }
}

static double blipp_read_core(CFIndex i) {
    BlippSMCParams input = {0}, output = {0};
    input.key = sCoreSensors[i].key;
    input.keyInfo = sCoreSensors[i].info;
    input.command = kBlippSMCReadBytes;
    if (!blipp_smc_call(&input, &output)) {
        return -1;
    }
    float value;
    memcpy(&value, output.bytes, sizeof value);
    return (value > 0 && value < 150) ? value : -1;
}

static double blipp_read_die(CFIndex i) {
    return blipp_read((IOHIDServiceClientRef)CFArrayGetValueAtIndex(sDieSensors, i));
}

// Keeps the latest reading per sensor. Each call refreshes only a slice of them
// (round robin), because every read is an IPC round trip and temperatures move slowly.
typedef struct {
    double *values;
    CFIndex cursor;
} BlippSensorCache;

static double blipp_average(BlippSensorCache *cache, CFIndex count, int budget, double (*read)(CFIndex)) {
    CFIndex reads = budget < 1 ? 1 : budget;
    if (cache->values == NULL) {
        cache->values = calloc((size_t)count, sizeof(double));
        if (cache->values == NULL) {
            return -1;
        }
        reads = count;  // first call: read everything once
    }
    if (reads > count) {
        reads = count;
    }
    for (CFIndex n = 0; n < reads; n++) {
        CFIndex i = (cache->cursor + n) % count;
        double value = read(i);
        if (value > 0) {
            cache->values[i] = value;
        }
    }
    cache->cursor = (cache->cursor + reads) % count;

    double sum = 0;
    int valid = 0;
    for (CFIndex i = 0; i < count; i++) {
        if (cache->values[i] > 0) {
            sum += cache->values[i];
            valid++;
        }
    }
    return valid > 0 ? sum / valid : -1;
}

static BlippSensorCache sCoreCache = {0};
static BlippSensorCache sDieCache = {0};

double blipp_cpu_temperature(int budget) {
    blipp_smc_setup();
    if (sCoreCount > 0) {
        double value = blipp_average(&sCoreCache, sCoreCount, budget, blipp_read_core);
        if (value > 0) {
            return value;
        }
    }

    blipp_setup();
    CFIndex dieCount = sDieSensors != NULL ? CFArrayGetCount(sDieSensors) : 0;
    if (dieCount > 0) {
        double value = blipp_average(&sDieCache, dieCount, budget, blipp_read_die);
        if (value > 0) {
            return value;
        }
    }

    // No die sensors by name on this chip: fall back to the hottest sensor we can read.
    if (sServices == NULL) {
        return -1;
    }
    double hottest = -1;
    CFIndex total = CFArrayGetCount(sServices);
    for (CFIndex i = 0; i < total; i++) {
        double value = blipp_read((IOHIDServiceClientRef)CFArrayGetValueAtIndex(sServices, i));
        if (value > hottest) {
            hottest = value;
        }
    }
    return hottest;
}

int blipp_core_sensor_count(void) {
    blipp_smc_setup();
    return (int)sCoreCount;
}

int blipp_die_sensor_count(void) {
    blipp_setup();
    return sDieSensors != NULL ? (int)CFArrayGetCount(sDieSensors) : 0;
}

void blipp_debug_dump_sensors(void) {
    blipp_setup();
    if (sServices == NULL) return;
    CFIndex total = CFArrayGetCount(sServices);
    for (CFIndex i = 0; i < total; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(sServices, i);
        CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        char buffer[128] = "?";
        if (name != NULL && CFGetTypeID(name) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)name, buffer, sizeof buffer, kCFStringEncodingUTF8);
        }
        if (name != NULL) CFRelease(name);
        printf("%-24s %6.2f\n", buffer, blipp_read(service));
    }
}
