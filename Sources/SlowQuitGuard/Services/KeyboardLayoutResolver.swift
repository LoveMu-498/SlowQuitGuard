// SPDX-License-Identifier: GPL-2.0-or-later
// Swift reimplementation of SlowQuitApps (2026-10-30).
// Reference: https://github.com/dteoh/SlowQuitApps
// Upstream copyright (C) 2020 Douglas Teoh.
// Copyright (C) 2026 SlowQuitGuard contributors.
// See NOTICE and LICENSE for attribution and terms.

import Carbon.HIToolbox
import Foundation

enum KeyboardLayoutResolver {
    static func qKeyCodes() -> Set<UInt16> {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return [UInt16(kVK_ANSI_Q)]
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return [UInt16(kVK_ANSI_Q)] }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var matches: Set<UInt16> = []
        for code: UInt16 in 0..<128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8),
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, characters.count, &length, &characters
            )
            if status == noErr,
               String(utf16CodeUnits: characters, count: length).lowercased() == "q" {
                matches.insert(code)
            }
        }
        return matches.isEmpty ? [UInt16(kVK_ANSI_Q)] : matches
    }
}
