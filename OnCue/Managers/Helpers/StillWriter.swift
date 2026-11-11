//
//  StillWriter.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/25/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation
import CoreVideo
import ImageIO
import VideoToolbox
import UniformTypeIdentifiers

/// One still beside every recording (spec 0053): the frame in hand when the file starts, written
/// as a JPEG under the movie's name, so a folder of recordings reads as a contact sheet in Finder.
enum StillWriter {
  /// JPEG quality. High enough that a face in a doorway survives, well under the movie's size.
  static let quality = 0.8

  /// The still's name is the movie's with the extension swapped, which is what keeps the pair
  /// together in Finder and inside the rolling window's grouping.
  static func stillURL(for movieURL: URL) -> URL {
    return movieURL.deletingPathExtension().appendingPathExtension("jpg")
  }

  /// The frame as JPEG bytes, or nil if the buffer's format can't be drawn. No Metal and no
  /// AppKit: VideoToolbox reads the capture format (32BGRA) straight from the buffer.
  static func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
    var image: CGImage?
    guard VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image) == noErr,
      let cgImage = image else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  /// Writes the frame beside the movie, private to its owner like the recording itself (spec 0017
  /// lets the folder be anywhere). Returns whether a still is now on disk.
  @discardableResult
  static func write(_ pixelBuffer: CVPixelBuffer, besideMovie movieURL: URL) -> Bool {
    guard let data = jpegData(from: pixelBuffer) else { return false }
    let url = stillURL(for: movieURL)
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      print("Could not write \(url.lastPathComponent): \(error.localizedDescription)")
      return false
    }
    FileOutputManager.makePrivate(url, permissions: 0o600)
    return true
  }

  /// Takes the still away when its movie never became a file. A still with no movie is worse
  /// than no still.
  static func removeStill(besideMovie movieURL: URL) {
    try? FileManager.default.removeItem(at: stillURL(for: movieURL))
  }
}
