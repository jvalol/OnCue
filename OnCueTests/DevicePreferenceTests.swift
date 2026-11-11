//
//  DevicePreferenceTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class DevicePreferenceTests: XCTestCase {
  func preferred(_ savedID: String?, _ available: [String]) -> String? {
    DevicePreference.preferred(savedID: savedID, available: available) { $0 }
  }

  func testUsesTheChosenDeviceWhenConnected() {
    XCTAssertEqual(preferred("webcam", ["built-in", "webcam"]), "webcam")
  }

  func testFallsBackToTheFirstWhenTheChosenOneIsGone() {
    XCTAssertEqual(preferred("webcam", ["built-in"]), "built-in")
  }

  func testUsesTheFirstWhenNothingWasChosen() {
    XCTAssertEqual(preferred(nil, ["built-in", "webcam"]), "built-in")
  }

  func testNothingConnectedMeansNoDevice() {
    XCTAssertNil(preferred("webcam", []))
  }

  func testFallsBackToTheGivenDeviceBeforeTheFirst() {
    XCTAssertEqual(DevicePreference.preferred(savedID: "usb", available: ["built-in", "system"], fallback: "system") { $0 }, "system")
    XCTAssertEqual(DevicePreference.preferred(savedID: nil, available: ["built-in", "system"], fallback: "system") { $0 }, "system")
    XCTAssertEqual(DevicePreference.preferred(savedID: "usb", available: ["built-in", "usb"], fallback: "system") { $0 }, "usb")
  }

  func testTheSecondCameraIsTheChosenOneWhenConnected() {
    XCTAssertEqual(DevicePreference.second(savedID: "webcam", available: ["built-in", "webcam"], firstID: "built-in") { $0 }, "webcam")
  }

  func testNoSecondCameraWithoutAChoiceOrWhenItsGone() {
    XCTAssertNil(DevicePreference.second(savedID: nil, available: ["built-in", "webcam"], firstID: "built-in") { $0 })
    XCTAssertNil(DevicePreference.second(savedID: "webcam", available: ["built-in"], firstID: "built-in") { $0 })
  }

  func testTheSecondCameraIsNeverTheFirst() {
    XCTAssertNil(DevicePreference.second(savedID: "webcam", available: ["built-in", "webcam"], firstID: "webcam") { $0 })
  }

  func testTheSecondCameraIsNeverOfferedTheFirstOne() {
    XCTAssertEqual(DevicePreference.secondChoices(available: ["built-in", "webcam"], firstID: "built-in") { $0 }, ["webcam"])
    XCTAssertEqual(DevicePreference.secondChoices(available: ["built-in"], firstID: "built-in") { $0 }, [])
  }

  func testChoosingNoCameraMeansNoDevice() {
    XCTAssertNil(preferred(DevicePreference.noDevice, ["built-in", "webcam"]))
    XCTAssertEqual(DevicePreference.preferred(savedID: DevicePreference.noDevice,
                                              available: ["built-in"], fallback: "built-in") { $0 }, nil)
  }

  func testNothingChosenStillFallsBack() {
    XCTAssertEqual(preferred(nil, ["built-in"]), "built-in")
  }

  func testACameraConnectingDoesNotUndoChoosingNoCamera() {
    XCTAssertFalse(DevicePreference.shouldSwitch(toConnectedID: "webcam", currentID: nil,
                                                 savedID: DevicePreference.noDevice))
  }

  /// A single camera is always the first one, so no first camera means no second either, and
  /// nothing is offered for the second slot.
  func testWithNoFirstCameraThereIsNoSecond() {
    XCTAssertNil(DevicePreference.second(savedID: "webcam", available: ["webcam"], firstID: nil) { $0 })
    XCTAssertEqual(DevicePreference.secondChoices(available: ["built-in", "webcam"], firstID: nil) { $0 }, [])
  }

  /// Settings used to ask for the first camera by the saved choice while showing the one in use.
  /// Unplug the chosen webcam and both pickers named the built-in camera, while capture quietly
  /// ran one. Asking the same question once keeps them together.
  func testUnpluggingTheFirstCameraDoesNotLeaveTheSameCameraInBothPickers() {
    let connected = ["built-in"]
    let first = DevicePreference.preferred(savedID: "webcam", available: connected, fallback: "built-in") { $0 }
    XCTAssertEqual(first, "built-in")

    let choices = DevicePreference.secondChoices(available: connected, firstID: first) { $0 }
    XCTAssertEqual(choices, [])
    XCTAssertNil(DevicePreference.second(savedID: "built-in", available: choices, firstID: first) { $0 })
  }

  func testATriggerRecordsOnEveryRunningCamera() {
    XCTAssertEqual(DevicePreference.recordingPipelines([(true, true, true), (true, true, true)]), [0, 1])
    XCTAssertEqual(DevicePreference.recordingPipelines([(true, true, true), (false, false, false)]), [0])
    XCTAssertEqual(DevicePreference.recordingPipelines([(true, false, true), (false, false, false)]), [0])
    XCTAssertEqual(DevicePreference.recordingPipelines([(false, false, false), (false, false, false)]), [])
  }

  func testAConnectingDeviceIsUsedWhenNoneIsInUse() {
    XCTAssertTrue(DevicePreference.shouldSwitch(toConnectedID: "webcam", currentID: nil, savedID: nil))
  }

  func testTheChosenDeviceReturningReplacesTheFallback() {
    XCTAssertTrue(DevicePreference.shouldSwitch(toConnectedID: "webcam", currentID: "built-in", savedID: "webcam"))
  }

  func testAnotherDeviceConnectingChangesNothing() {
    XCTAssertFalse(DevicePreference.shouldSwitch(toConnectedID: "other", currentID: "built-in", savedID: "webcam"))
    XCTAssertFalse(DevicePreference.shouldSwitch(toConnectedID: "other", currentID: "webcam", savedID: "webcam"))
  }

  func testTheChosenDeviceAlreadyInUseChangesNothing() {
    XCTAssertFalse(DevicePreference.shouldSwitch(toConnectedID: "webcam", currentID: "webcam", savedID: "webcam"))
  }

  // MARK: - Triggers and device choices (spec 0028)

  func testChoosingNoDeviceSwitchesItsTriggerOff() {
    XCTAssertFalse(DevicePreference.triggerEnabled(wasEnabled: true, choosingNone: true))
  }

  func testChoosingADeviceLeavesTheTriggerAsItWas() {
    XCTAssertTrue(DevicePreference.triggerEnabled(wasEnabled: true, choosingNone: false))
    XCTAssertFalse(DevicePreference.triggerEnabled(wasEnabled: false, choosingNone: false))
  }

  /// Choosing none can't switch a trigger on that was already off.
  func testChoosingNoneNeverTurnsATriggerOn() {
    XCTAssertFalse(DevicePreference.triggerEnabled(wasEnabled: false, choosingNone: true))
  }

  /// A device going missing isn't a choice, so its trigger survives to resume when it returns.
  /// That path doesn't call this rule at all; `shouldSwitch` is what handles the device coming
  /// back, and it already refuses to override a deliberate none.
  func testADeviceGoingMissingIsNotAChoice() {
    XCTAssertTrue(DevicePreference.triggerEnabled(wasEnabled: true, choosingNone: false))
    XCTAssertFalse(DevicePreference.shouldSwitch(toConnectedID: "mic", currentID: nil,
                                                 savedID: DevicePreference.noDevice))
    XCTAssertTrue(DevicePreference.shouldSwitch(toConnectedID: "mic", currentID: nil, savedID: nil))
  }
}
