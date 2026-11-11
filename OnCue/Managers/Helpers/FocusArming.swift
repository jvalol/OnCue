//
//  FocusArming.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

/// What a Focus Filter asks of OnCue (spec 0050), decided the way the schedule decides (0038):
/// a Focus that wants OnCue armed arms it if nothing else has; a Focus ending disarms only what a
/// Focus armed. A manual arm, a login arm or a schedule arm is never undone by a Focus, and a
/// Focus without the switch says nothing at all.
enum FocusArming {
  enum Action: Equatable {
    case none, arm, disarm
  }

  static func action(wantsArmed: Bool, state: RecordingManager.ArmState, armedByFocus: Bool, canFire: Bool) -> Action {
    if wantsArmed {
      return state == .unarmed && canFire ? .arm : .none
    }
    return armedByFocus && state != .unarmed ? .disarm : .none
  }
}
