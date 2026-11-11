//
//  LoginItem.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation
import ServiceManagement

/// What LoginItem needs from macOS's login items, so tests can stand in a fake.
protocol LoginItemService {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Whether OnCue opens at login (spec 0015). macOS's login items are the only record, so Settings
/// always shows what System Settings shows.
struct LoginItem {
  /// Posted on the main thread when Settings changes the login item, with the new `State` under
  /// `stateKey`, so the popover's notice follows without being reopened (spec 0051).
  static let stateChanged = Notification.Name("OnCue.loginItemStateChanged")
  static let stateKey = "state"

  enum State: Equatable {
    case on, off, needsApproval
  }

  let service: LoginItemService

  static let app = LoginItem(service: SMAppService.mainApp)

  static func state(for status: SMAppService.Status) -> State {
    switch status {
    case .enabled: return .on
    case .requiresApproval: return .needsApproval
    default: return .off
    }
  }

  var state: State {
    LoginItem.state(for: service.status)
  }

  /// Whether Settings shows the box checked. macOS reports a login item the user switched off in
  /// System Settings as needing approval, so that reads as off, not as something pending.
  static func isChecked(_ state: State) -> Bool {
    return state == .on
  }

  /// Turns opening at login on or off, and reports the state macOS ends up in, with the error if
  /// the change failed.
  func set(_ on: Bool) -> (state: State, error: Error?) {
    do {
      if on {
        try service.register()
      } else {
        try service.unregister()
      }
      return (state, nil)
    } catch {
      return (state, error)
    }
  }
}
