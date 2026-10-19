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

import Darwin
import Foundation
import Network

/// Sums traffic over all non-loopback interfaces using 64-bit interface counters.
final class NetworkSampler {
    private var previous: (received: UInt64, sent: UInt64, time: TimeInterval)?
    private let pathMonitor = NWPathMonitor()
    private(set) var online = true

    init(queue: DispatchQueue) {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.online = path.status == .satisfied
        }
        pathMonitor.start(queue: queue)
    }

    deinit {
        pathMonitor.cancel()
    }

    func sample(now: TimeInterval) -> (down: Double, up: Double) {
        guard let totals = readCounters() else { return (0, 0) }
        defer { previous = (totals.received, totals.sent, now) }
        guard let previous, now > previous.time else { return (0, 0) }

        let elapsed = now - previous.time
        let down = totals.received >= previous.received ? Double(totals.received - previous.received) / elapsed : 0
        let up = totals.sent >= previous.sent ? Double(totals.sent - previous.sent) / elapsed : 0
        return (down, up)
    }

    private func readCounters() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 8)
        defer { buffer.deallocate() }
        guard sysctl(&mib, 6, buffer, &length, nil, 0) == 0 else { return nil }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            if header.ifm_msglen == 0 { break }
            if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                let header2 = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if header2.ifm_flags & IFF_LOOPBACK == 0 {
                    received &+= header2.ifm_data.ifi_ibytes
                    sent &+= header2.ifm_data.ifi_obytes
                }
            }
            offset += Int(header.ifm_msglen)
        }
        return (received, sent)
    }
}
