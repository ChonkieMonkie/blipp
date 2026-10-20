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

#ifndef CSENSORS_H
#define CSENSORS_H

/// Average CPU core temperature in °C, read from the SMC's core sensors, or from the
/// chip's HID die sensors when the SMC has none.
/// Every sensor read is a slow round trip, so each call reads only `budget` sensors
/// (round robin) and averages them with the latest values of the rest.
/// Returns a negative value when no sensor could be read.
double blipp_cpu_temperature(int budget);

/// Number of SMC CPU core sensors found (for diagnostics).
int blipp_core_sensor_count(void);

/// Number of HID die sensors found (for diagnostics).
int blipp_die_sensor_count(void);

/// Prints every temperature sensor and its value (diagnostics).
void blipp_debug_dump_sensors(void);

#endif
