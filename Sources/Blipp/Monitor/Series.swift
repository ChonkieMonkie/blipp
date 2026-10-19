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

import Foundation

/// A rolling time series that keeps up to an hour of samples.
struct Series {
    private(set) var times: [TimeInterval] = []
    private(set) var values: [Double] = []
    let maxAge: TimeInterval

    init(maxAge: TimeInterval = 3600) {
        self.maxAge = maxAge
    }

    mutating func append(_ value: Double, at time: TimeInterval) {
        times.append(time)
        values.append(value)
        // Trim in batches (10 % overshoot) instead of shifting the arrays on every sample.
        if let first = times.first, first < time - maxAge * 1.1 {
            let drop = index(atOrAfter: time - maxAge)
            times.removeFirst(drop)
            values.removeFirst(drop)
        }
    }

    func average(since start: TimeInterval) -> Double? {
        let from = index(atOrAfter: start)
        guard from < values.count else { return nil }
        var sum = 0.0
        for index in from..<values.count { sum += values[index] }
        return sum / Double(values.count - from)
    }

    /// Averages the samples inside `span` into about `buckets` points placed on a 0…1 time axis.
    ///
    /// Buckets are fixed slices of the clock, not of the window: a sample stays in the same bucket
    /// for as long as it's shown, so the graph scrolls instead of reshaping on every update.
    func points(span: TimeInterval, now: TimeInterval, buckets: Int = 90) -> [GraphPoint] {
        let start = now - span
        let width = span / Double(buckets)
        let firstBucket = (start / width).rounded(.down)
        let firstIndex = index(atOrAfter: firstBucket * width)
        guard firstIndex < times.count else { return [] }

        // One extra slot: the window's edges cut through the oldest and the newest bucket.
        let slots = buckets + 1
        var sums = [Double](repeating: 0, count: slots)
        var counts = [Int](repeating: 0, count: slots)
        for index in firstIndex..<times.count {
            let bucket = min(slots - 1, max(0, Int((times[index] / width).rounded(.down) - firstBucket)))
            sums[bucket] += values[index]
            counts[bucket] += 1
        }

        var points: [GraphPoint] = []
        points.reserveCapacity(slots)
        for bucket in 0..<slots where counts[bucket] > 0 {
            let middle = (firstBucket + Double(bucket) + 0.5) * width
            let x = min(1, max(0, (middle - start) / span))
            points.append(GraphPoint(x: x, value: sums[bucket] / Double(counts[bucket])))
        }
        if var last = points.last {
            last.x = 1
            points[points.count - 1] = last
        }
        return points
    }

    /// Binary search: the first sample taken at or after `time`.
    private func index(atOrAfter time: TimeInterval) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
