//
//  RecordingFailure.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne
//

import AVFoundation

/// Why a recording didn't get written, in the terms a person can act on (spec 0027). A failure
/// used to be printed to a console nobody reads while the icon stayed red and the popover said
/// Recording, so OnCue looked exactly like it was working.
///
/// Unlike spec 0024, where a short file survives to be found later, there's no file here at all.
/// The app is the only place this can ever be said.
enum RecordingFailure: Equatable {
  /// No room left where recordings go.
  case diskFull
  /// The folder isn't reachable: unplugged, unmounted, or gone.
  case destinationMissing
  /// OnCue isn't allowed to write there any more.
  case notPermitted
  /// Something else went wrong.
  case other

  /// What an `Error` from the recorder means. Only the cases worth telling apart are told apart;
  /// the rest share a plain sentence rather than repeating Foundation's wording at people.
  static func from(_ error: Error) -> RecordingFailure {
    let error = error as NSError
    if error.domain == NSPOSIXErrorDomain {
      switch Int32(error.code) {
      case ENOSPC, EDQUOT: return .diskFull
      case ENOENT, ENXIO, ENODEV: return .destinationMissing
      case EACCES, EPERM, EROFS: return .notPermitted
      default: return .other
      }
    }
    if error.domain == NSCocoaErrorDomain {
      switch error.code {
      case NSFileWriteOutOfSpaceError: return .diskFull
      case NSFileWriteVolumeReadOnlyError: return .notPermitted
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .destinationMissing
      case NSFileWriteNoPermissionError: return .notPermitted
      default: break
      }
    }
    // AVFoundation wraps the real cause, so the underlying error is where the reason lives.
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
      return from(underlying)
    }
    return .other
  }

  /// The popover's notice for `count` failures in a row: one whole sentence per case, each with
  /// its singular in the catalog, so a translation can order the words its own way (spec 0043).
  /// One failure is bad luck; a run of them is a setup that needs fixing (spec 0027).
  func notice(count: Int) -> String {
    switch self {
    case .diskFull:
      return String(localized: "\(count) recordings in a row weren't saved: there's no room left where recordings go", comment: "Popover notice; has a singular form in the catalog")
    case .destinationMissing:
      return String(localized: "\(count) recordings in a row weren't saved: the folder recordings go to isn't there", comment: "Popover notice; has a singular form in the catalog")
    case .notPermitted:
      return String(localized: "\(count) recordings in a row weren't saved: OnCue isn't allowed to write where recordings go", comment: "Popover notice; has a singular form in the catalog")
    case .other:
      return String(localized: "\(count) recordings in a row weren't saved: the file couldn't be written", comment: "Popover notice; has a singular form in the catalog")
    }
  }

  /// Whether a finished recording is worth saying anything about. A recording that never captured
  /// anything isn't a failure to write: nothing was there to write, and the file is already gone.
  static func isWorthSaying(_ error: Error?) -> Bool {
    guard let error = error as NSError? else { return false }
    return !(error.domain == AVFoundationErrorDomain && error.code == AVError.noDataCaptured.rawValue)
  }
}
