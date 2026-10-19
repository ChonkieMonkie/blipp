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

// Latest reading per die sensor. Each call refreshes only a slice of them (round robin),
// because every read is an IPC round trip and die temperatures move slowly.
static double *sDieValues = NULL;
static CFIndex sDieCursor = 0;

double blipp_cpu_temperature(int budget) {
    blipp_setup();

    CFIndex dieCount = sDieSensors != NULL ? CFArrayGetCount(sDieSensors) : 0;
    if (dieCount > 0) {
        CFIndex reads = budget < 1 ? 1 : budget;
        if (sDieValues == NULL) {
            sDieValues = calloc((size_t)dieCount, sizeof(double));
            reads = dieCount;  // first call: read everything once
        }
        if (reads > dieCount) {
            reads = dieCount;
        }
        if (sDieValues != NULL) {
            for (CFIndex n = 0; n < reads; n++) {
                CFIndex i = (sDieCursor + n) % dieCount;
                double value = blipp_read((IOHIDServiceClientRef)CFArrayGetValueAtIndex(sDieSensors, i));
                if (value > 0) {
                    sDieValues[i] = value;
                }
            }
            sDieCursor = (sDieCursor + reads) % dieCount;

            double sum = 0;
            int count = 0;
            for (CFIndex i = 0; i < dieCount; i++) {
                if (sDieValues[i] > 0) {
                    sum += sDieValues[i];
                    count++;
                }
            }
            if (count > 0) {
                return sum / count;
            }
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
