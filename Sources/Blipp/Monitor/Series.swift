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

    /// Averages the samples inside `span` into at most `buckets` points placed on a 0…1 time axis.
    func points(span: TimeInterval, now: TimeInterval, buckets: Int = 90) -> [GraphPoint] {
        let start = now - span
        let firstIndex = index(atOrAfter: start)
        guard firstIndex < times.count else { return [] }

        var sums = [Double](repeating: 0, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)
        for index in firstIndex..<times.count {
            let position = (times[index] - start) / span
            let bucket = min(buckets - 1, max(0, Int(position * Double(buckets))))
            sums[bucket] += values[index]
            counts[bucket] += 1
        }

        var points: [GraphPoint] = []
        points.reserveCapacity(buckets)
        for bucket in 0..<buckets where counts[bucket] > 0 {
            let x = (Double(bucket) + 0.5) / Double(buckets)
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
