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

/// Everything needed to draw Blipp in one frame. The mood engine decides the scene;
/// the renderer only draws it.
///
/// Every metric owns one part of Blipp and never touches another: the face is CPU, the body
/// color (and sweat) is temperature, above the head is memory, the left hand is network, the
/// right hand is disk and the sticker at his feet is battery. Emergencies change the whole figure.
struct BlippScene: Hashable {
    enum Shape: Hashable {
        case normal, puddle
    }

    enum Face: Hashable {
        // CPU
        case sleeping, smile, sunglasses, focused, sweaty, panic
        // Emergencies
        case dead, boiling
        // Only for a moment, in the panel's opening animations
        case happyClosed, wink, excited, yawn, relieved, surprised
    }

    /// Speed lines on the sides, stronger with CPU load.
    enum Work: Hashable { case none, light, strong }

    /// Temperature extras on top of the body color. Fire (steam and a flame on his head)
    /// is only for critical heat.
    enum Heat: Hashable { case none, sweat, steam, fire }

    /// Above the head: memory first; Zzz and the gear only when memory leaves the spot free.
    enum Head: Hashable { case none, zzz, gear, juggle3, juggle5, swapBox }

    /// Left hand: network.
    enum Network: Hashable { case none, download, upload, both, offline }

    /// Right hand: disk.
    enum Disk: Hashable { case none, read, write, both }

    /// The sticker at his feet: battery.
    enum Sticker: Hashable { case none, juice, cookie, limit, low }

    var shape: Shape = .normal
    var color: UInt32 = Palette.mint
    var face: Face = .smile
    var work: Work = .none
    var heat: Heat = .none
    var head: Head = .none
    var network: Network = .none
    var disk: Disk = .none
    var sticker: Sticker = .none
    var shake = false
    var bobPeriod: Double = 2.4

    /// Sweat drops show from "hot" and up, in the menu bar too.
    var sweat: Bool { heat != .none }
}

enum Palette {
    static let ink: UInt32 = 0x22303F
    static let chilly: UInt32 = 0xA9D8F5
    static let mint: UInt32 = 0x8EE0BF
    static let warm: UInt32 = 0xFFD98A
    static let orange: UInt32 = 0xFFB36B
    static let hot: UInt32 = 0xFF7A59
    static let boiling: UInt32 = 0xFF6A4D
    static let flame: UInt32 = 0xFFB020
    static let flameCore: UInt32 = 0xFFE27A
    static let melted: UInt32 = 0xC9CFD6
    static let cheek: UInt32 = 0xFF7FA0
    static let tongue: UInt32 = 0xFF7FA0
    static let sweat: UInt32 = 0x7CC8FF
    static let juice: UInt32 = 0xFFD166
    static let straw: UInt32 = 0xFF5D8F
    static let cookie: UInt32 = 0xE9B872
    static let cardboard: UInt32 = 0xD9A86C
    static let cardboardLight: UInt32 = 0xE8C08A
    static let cardboardDark: UInt32 = 0xC38F55
    static let tape: UInt32 = 0xF1D7A8
    static let steel: UInt32 = 0xC9D3DD
    static let red: UInt32 = 0xE5484D
    static let green: UInt32 = 0x22A06B
    // The panel's graph colors, so a prop matches the line it stands for.
    static let download: UInt32 = 0x3D7BF0
    static let upload: UInt32 = 0xA474F2
    static let read: UInt32 = 0x3D7BF0
    static let write: UInt32 = 0xF43F5E
    static let pencilTip: UInt32 = 0xFCD9C0
    static let ballPink: UInt32 = 0xFF5D8F
    static let ballBlue: UInt32 = 0x6EC6FF
    static let ballYellow: UInt32 = 0xFFD166
    static let ballPurple: UInt32 = 0xB79CFF
    static let ballOrange: UInt32 = 0xFF8A3D
    static let white: UInt32 = 0xFFFFFF
}
