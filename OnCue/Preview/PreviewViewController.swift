//
//  PreviewViewController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 11/14/19.
//  Copyright © 2019 Jake Van Alstyne
//

import Cocoa
import AVFoundation

class PreviewViewController: NSViewController, CaptureManagerPreviewDelegate {
  @IBOutlet weak private var previewView: PreviewMetalView!

  /// The second camera's preview, beside the first while there's a second camera (spec 0012).
  private let secondPreviewView = PreviewMetalView()
  private var cameraNames: [String] = []
  private var aspectRatio: CGSize?
  /// Zones are drawn over each preview (spec 0042); each editor is bound to its camera's ID and
  /// told where the picture sits whenever a frame arrives.
  private let zoneEditor = ZoneEditorView(frame: .zero)
  private let secondZoneEditor = ZoneEditorView(frame: .zero)

  override func viewDidLoad() {
    // The storyboard's view is the first camera's preview. Put it in a row with the second.
    let row = NSStackView(views: [previewView, secondPreviewView])
    row.orientation = .horizontal
    row.distribution = .fillEqually
    row.spacing = 0
    row.frame = previewView.frame
    secondPreviewView.isHidden = true
    view = row
    for (preview, editor) in [(previewView!, zoneEditor), (secondPreviewView, secondZoneEditor)] {
      editor.frame = preview.bounds
      editor.autoresizingMask = [.width, .height]
      preview.addSubview(editor)
    }
    applyCameraIDs()

    AppDelegate.captureManager.previewDelegate = self
    // Capture may have been configured before this window existed.
    cameraNames = [AppDelegate.captureManager.currentVideoCaptureDevice, AppDelegate.captureManager.currentSecondVideoCaptureDevice]
      .compactMap { $0?.localizedName }

    guard let ratio = AppDelegate.captureManager.aspectRatio else { return }
    setAspectRatio(ratio)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    applyCameras()
  }

  /// Once more with the window at its final size: two cameras want a window twice as wide, and
  /// whatever the window is before it appears isn't necessarily what it is after.
  override func viewDidAppear() {
    super.viewDidAppear()
    applyCameras()
  }

  func setCameraNames(_ names: [String]) {
    cameraNames = names
    applyCameras()
    applyCameraIDs()
  }

  /// Which camera each editor's zones belong to. Names arrive with the devices, so this follows.
  private func applyCameraIDs() {
    let captureManager = AppDelegate.captureManager
    zoneEditor.cameraID = captureManager.currentVideoCaptureDevice?.uniqueID
    secondZoneEditor.cameraID = captureManager.currentSecondVideoCaptureDevice?.uniqueID
  }

  func setAspectRatio(_ ratio: CGSize) {
    aspectRatio = ratio
    applyCameras()
  }

  /// Title, second preview, and window shape follow the cameras in use. Two cameras sit side by
  /// side, so the window is twice as wide for the same height.
  private func applyCameras() {
    let two = cameraNames.count > 1
    secondPreviewView.isHidden = !two
    view.window?.title = PreviewTitle.title(cameraNames: cameraNames)
    guard let window = view.window, let ratio = aspectRatio, ratio.height > 0 else { return }
    let aspect = CGSize(width: ratio.width * (two ? 2 : 1), height: ratio.height)
    window.contentAspectRatio = aspect
    // The aspect ratio only holds for later resizing, so fit the window to the cameras now;
    // otherwise the views letterbox inside whatever shape the window already had.
    window.setContentSize(PreviewTitle.contentSize(fitting: aspect,
                                                   width: window.contentLayoutRect.width,
                                                   maximum: window.screen?.visibleFrame.size))
  }

  func setPreviewBuffer(_ buffer: CVPixelBuffer, camera: Int) {
    let (preview, editor) = camera == 0 ? (previewView!, zoneEditor) : (secondPreviewView, secondZoneEditor)
    preview.pixelBuffer = buffer
    // The picture's place in the view is known once a frame has been drawn; keep the editor over it.
    DispatchQueue.main.async {
      editor.pictureRect = preview.pictureRect
    }
  }
}
