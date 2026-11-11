//
//  MotionDetectMetalRenderer.metal
//  OnCue
//
//  Created by Jake Van Alstyne on 12/20/19.
//  Copyright © 2019 Jake Van Alstyne
//

import CoreMedia
import CoreVideo
import Metal
import MetalPerformanceShaders

class MotionDetectMetalRenderer: FilterRenderer {
  var description: String = "Motion Detect"
  var isPrepared = false
  private(set) var inputFormatDescription: CMFormatDescription?
  private(set) var outputFormatDescription: CMFormatDescription?
  private var outputPixelBufferPool: CVPixelBufferPool?
  private let metalDevice = MTLCreateSystemDefaultDevice()!
  /// Two variants of the one kernel (spec 0041): with the preview write, and without it for the
  /// frames nobody is looking at. Chosen per call by `renderWithPreview`'s flag.
  private var computePipelineState: MTLComputePipelineState?
  private var maskOnlyPipelineState: MTLComputePipelineState?
  private var textureCache: CVMetalTextureCache!

  #if DEBUG
  private var measuredGPUSeconds = 0.0
  private var measuredFrames = 0
  #endif

  private lazy var commandQueue: MTLCommandQueue? = {
    return self.metalDevice.makeCommandQueue()
  }()

  required init() {
    let defaultLibrary = metalDevice.makeDefaultLibrary()!
    for writesPreview in [true, false] {
      let constants = MTLFunctionConstantValues()
      var value = writesPreview
      constants.setConstantValue(&value, type: .bool, index: 0)
      do {
        let kernelFunction = try defaultLibrary.makeFunction(name: "motionDetect", constantValues: constants)
        let state = try metalDevice.makeComputePipelineState(function: kernelFunction)
        if writesPreview { computePipelineState = state } else { maskOnlyPipelineState = state }
      } catch {
        print("Could not create pipeline state: \(error)")
      }
    }
  }

  func prepare(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
    reset()

    (outputPixelBufferPool, _, outputFormatDescription) = allocateOutputBufferPool(with: formatDescription,
                                                                                   outputRetainedBufferCountHint: outputRetainedBufferCountHint)
    if outputPixelBufferPool == nil {
      return
    }
    inputFormatDescription = formatDescription

    var metalTextureCache: CVMetalTextureCache?
    if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
      // A runtime failure, not a programmer error, so it isn't an assertion. The pipeline calls
      // prepare again on the next frame while this is unprepared, so a passing one recovers.
      print("Could not allocate the motion detect texture cache")
    } else {
      textureCache = metalTextureCache
    }

    // Only ready when everything it renders with exists. This used to be set unconditionally, so a
    // texture cache that failed to allocate left the renderer claiming to be prepared, and the
    // next frame handed that nil cache to CoreVideo and took the app down with it. Saying no is
    // also what gets it retried: the pipeline prepares again on every frame until this is true.
    isPrepared = textureCache != nil
  }

  func reset() {
    outputPixelBufferPool = nil
    outputFormatDescription = nil
    inputFormatDescription = nil
    textureCache = nil
    isPrepared = false
  }

  /// The mask alone, for the protocol. The pipeline uses `renderWithPreview` and asks for both
  /// only while something is showing the preview.
  func render(lastPixelBuffer: CVPixelBuffer, currentPixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    return renderWithPreview(lastPixelBuffer: lastPixelBuffer, currentPixelBuffer: currentPixelBuffer, preview: false)?.mask
  }

  /// One pass, one or two buffers: `mask` is what the sampler counts, unchanged since 2019;
  /// `preview` is the picture with changed pixels under a translucent red (spec 0040), written
  /// only when asked for, since nothing shows it while the preview window is closed (spec 0041).
  /// - Tag: FilterMetalMotionDetect
  func renderWithPreview(lastPixelBuffer: CVPixelBuffer, currentPixelBuffer: CVPixelBuffer,
                         preview wantsPreview: Bool) -> (mask: CVPixelBuffer, preview: CVPixelBuffer?)? {
    if !isPrepared {
      assertionFailure("Invalid state: Not prepared.")
      return nil
    }
    guard let pipelineState = wantsPreview ? computePipelineState : maskOnlyPipelineState else {
      return nil
    }

    var newPixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newPixelBuffer)
    guard let outputPixelBuffer = newPixelBuffer else {
      print("Allocation failure: Could not get pixel buffer from pool. (\(self.description))")
      return nil
    }
    guard let lastFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: lastPixelBuffer, textureFormat: .bgra8Unorm),
      let currentFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: currentPixelBuffer, textureFormat: .bgra8Unorm),
      let outputTexture = makeTextureFromCVPixelBuffer(pixelBuffer: outputPixelBuffer, textureFormat: .bgra8Unorm) else {
        return nil
    }
    // The preview buffer and its texture exist only when asked for.
    var previewPixelBuffer: CVPixelBuffer?
    var previewTexture: MTLTexture?
    if wantsPreview {
      CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &previewPixelBuffer)
      guard let buffer = previewPixelBuffer,
        let texture = makeTextureFromCVPixelBuffer(pixelBuffer: buffer, textureFormat: .bgra8Unorm) else {
          print("Allocation failure: Could not get a preview buffer from pool. (\(self.description))")
          return nil
      }
      previewTexture = texture
    }

    // Set up command queue, buffer, and encoder.
    guard let commandQueue = commandQueue,
      let commandBuffer = commandQueue.makeCommandBuffer() else {
        print("Failed to create a Metal command queue.")
        CVMetalTextureCacheFlush(textureCache!, 0)
        return nil
    }

    var newCurrentSmoothedPixelBuffer: CVPixelBuffer?
    var newPreviousSmoothedPixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newCurrentSmoothedPixelBuffer)
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newPreviousSmoothedPixelBuffer)
    guard let currentSmoothedPixelBuffer = newCurrentSmoothedPixelBuffer,
      let previousSmoothedPixelBuffer = newPreviousSmoothedPixelBuffer else {
        print("Allocation failure: Could not get pixel buffer from pool. (\(self.description))")
        return nil
    }

    guard let currentSmoothedFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: currentSmoothedPixelBuffer, textureFormat: .bgra8Unorm),
      let lastSmoothedFrameTexture = makeTextureFromCVPixelBuffer(pixelBuffer: previousSmoothedPixelBuffer, textureFormat: .bgra8Unorm) else {
        return nil
    }

    let gaussianBlur = MPSImageGaussianBlur.init(device: self.metalDevice, sigma: 1.5)
    gaussianBlur.encode(commandBuffer: commandBuffer, sourceTexture: lastFrameTexture, destinationTexture: lastSmoothedFrameTexture)
    gaussianBlur.encode(commandBuffer: commandBuffer, sourceTexture: currentFrameTexture, destinationTexture: currentSmoothedFrameTexture)

    guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
      print("Failed to create a Metal command encoder.")
      CVMetalTextureCacheFlush(textureCache!, 0)
      return nil
    }

    commandEncoder.label = "Motion Detect Metal"
    commandEncoder.setComputePipelineState(pipelineState)
    commandEncoder.setTexture(lastSmoothedFrameTexture, index: 0)
    commandEncoder.setTexture(currentSmoothedFrameTexture, index: 1)
    commandEncoder.setTexture(outputTexture, index: 2)
    if let previewTexture = previewTexture {
      commandEncoder.setTexture(previewTexture, index: 3)
      // The preview is drawn from the unblurred frame; the diff runs on the blurred ones.
      commandEncoder.setTexture(currentFrameTexture, index: 4)
    }

    // Set up the thread groups.
    let width = pipelineState.threadExecutionWidth
    let height = pipelineState.maxTotalThreadsPerThreadgroup / width
    let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
    let threadgroupsPerGrid = MTLSize(width: (lastFrameTexture.width + width - 1) / width,
                                      height: (lastFrameTexture.height + height - 1) / height,
                                      depth: 1)
    commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

    commandEncoder.endEncoding()
    commandBuffer.commit()

    // The caller reads outputPixelBuffer on the CPU (motion detection) and hands it to the preview,
    // so the GPU must finish writing it before we return. Waiting also keeps the CVMetalTextures
    // backing the input and output textures alive for the duration of the work.
    commandBuffer.waitUntilCompleted()
    #if DEBUG
    // Debug builds only, and only with ONCUE_MEASURE set to a file path the sandbox can write
    // (~/Movies/OnCue/... is one): the GPU time of this pass, averaged, every 300 frames. Specs
    // 0039, 0040 and 0041 were measured with it; it costs nothing when the variable is unset.
    if let path = ProcessInfo.processInfo.environment["ONCUE_MEASURE"] {
      measuredGPUSeconds += commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
      measuredFrames += 1
      if measuredFrames % 300 == 0 {
        let line = String(format: "measure: %dx%d gpu %.3f ms/frame over %d frames\n",
                          CVPixelBufferGetWidth(currentPixelBuffer), CVPixelBufferGetHeight(currentPixelBuffer),
                          measuredGPUSeconds / Double(measuredFrames) * 1000, measuredFrames)
        if let handle = FileHandle(forWritingAtPath: path) ?? (FileManager.default.createFile(atPath: path, contents: nil) ? FileHandle(forWritingAtPath: path) : nil) {
          handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); handle.closeFile()
        }
      }
    }
    #endif
    if let error = commandBuffer.error {
      print("Motion detect command buffer failed: \(error)")
      return nil
    }

    return (outputPixelBuffer, previewPixelBuffer)
  }

  func makeTextureFromCVPixelBuffer(pixelBuffer: CVPixelBuffer, textureFormat: MTLPixelFormat) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // Create a Metal texture from the image buffer.
    var cvTextureOut: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut)
    guard status == kCVReturnSuccess else {
      print(status)

      CVMetalTextureCacheFlush(textureCache, 0)
      return nil
    }

    guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
      CVMetalTextureCacheFlush(textureCache, 0)

      return nil
    }

    return texture
  }
}
