#ifndef CSENSORS_H
#define CSENSORS_H

/// Average SoC die temperature in °C, read from the chip's HID thermal sensors.
/// Every sensor read is a slow round trip, so each call reads only `budget` sensors
/// (round robin) and averages them with the latest values of the rest.
/// Returns a negative value when no sensor could be read.
double blipp_cpu_temperature(int budget);

/// Number of CPU die sensors found (for diagnostics).
int blipp_die_sensor_count(void);

/// Prints every temperature sensor and its value (diagnostics).
void blipp_debug_dump_sensors(void);

#endif
