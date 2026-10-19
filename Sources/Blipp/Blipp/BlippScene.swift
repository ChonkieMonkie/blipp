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
struct BlippScene: Hashable {
    enum Shape: Hashable {
        case normal, squished, round, wide, puddle
    }

    enum Face: Hashable {
        case smile, sleeping, sunglasses, focused, sweaty, panic
        case happyClosed, chewing, content, pleased, tired, dead, dizzy
        case lookingUp, determined, relieved, licking, boiling
        case excited, wink, sad, surprised
    }

    enum Hands: Hashable {
        case none, juice, cookie, juiceAside, fan, iceCream
        case catchBox, plane, papers, packBox, thermometer
    }

    enum Overhead: Hashable {
        case none, zzz, gear, flame, juggle3, juggle5
        case cloudOffline, lowBattery, emptyBattery, batteryCheck, sparkles, steam
    }

    var shape: Shape = .normal
    var color: UInt32 = Palette.mint
    var face: Face = .smile
    var hands: Hands = .none
    var overhead: Overhead = .none
    var sweat = false
    var tear = false
    var shake = false
    var dizzy = false
    var bobPeriod: Double = 2.4
}

enum Palette {
    static let ink: UInt32 = 0x22303F
    static let sleepy: UInt32 = 0xA9D8F5
    static let mint: UInt32 = 0x8EE0BF
    static let lime: UInt32 = 0xC6E879
    static let warm: UInt32 = 0xFFD98A
    static let yellow: UInt32 = 0xFFC857
    static let orange: UInt32 = 0xFFB36B
    static let hot: UInt32 = 0xFF7A59
    static let boiling: UInt32 = 0xFF6A4D
    static let tired: UInt32 = 0xBFCFC8
    static let offline: UInt32 = 0xB7C9C1
    static let melted: UInt32 = 0xC9CFD6
    static let cheek: UInt32 = 0xFF7FA0
    static let tongue: UInt32 = 0xFF7FA0
    static let sweat: UInt32 = 0x7CC8FF
    static let juice: UInt32 = 0xFFD166
    static let straw: UInt32 = 0xFF5D8F
    static let cookie: UInt32 = 0xE9B872
    static let cardboard: UInt32 = 0xD9A86C
    static let steel: UInt32 = 0xC9D3DD
    static let red: UInt32 = 0xE5484D
    static let green: UInt32 = 0x22A06B
    static let ballPink: UInt32 = 0xFF5D8F
    static let ballBlue: UInt32 = 0x6EC6FF
    static let ballYellow: UInt32 = 0xFFD166
    static let ballPurple: UInt32 = 0xB79CFF
    static let ballOrange: UInt32 = 0xFF8A3D
    static let white: UInt32 = 0xFFFFFF
}
