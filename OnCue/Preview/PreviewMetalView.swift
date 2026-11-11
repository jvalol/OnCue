/*
 See LICENSE folder for this sample’s licensing information.

 Abstract:
 The Metal preview view.
 */

import CoreMedia
import Metal
import MetalKit

class PreviewMetalView: MTKView {
  var pixelBuffer: CVPixelBuffer? {
    didSet {
      syncQueue.sync {
        internalPixelBuffer = pixelBuffer
      }
    }
  }

  private var internalPixelBuffer: CVPixelBuffer?

  private let syncQueue = DispatchQueue(label: "Preview View Sync Queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)

  private var textureCache: CVMetalTextureCache?

  private var textureWidth: Int = 0

  private var textureHeight: Int = 0

  private var sampler: MTLSamplerState!

  private var renderPipelineState: MTLRenderPipelineState!

  private var commandQueue: MTLCommandQueue?

  private var vertexCoordBuffer: MTLBuffer!

  private var textCoordBuffer: MTLBuffer!

  private var internalBounds: CGRect!

  private var textureTranform: CGAffineTransform?

  /// Where the picture sits in the view: aspect-fitted and centred, the same arithmetic as
  /// `setupTransform`. Zero until a frame has been drawn. The zone editor draws over this.
  var pictureRect: CGRect {
    guard textureWidth > 0, textureHeight > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
    let scale = min(bounds.width / CGFloat(textureWidth), bounds.height / CGFloat(textureHeight))
    let size = CGSize(width: CGFloat(textureWidth) * scale, height: CGFloat(textureHeight) * scale)
    return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                  width: size.width, height: size.height)
  }

  func texturePointForView(point: CGPoint) -> CGPoint? {
    var result: CGPoint?
    guard let transform = textureTranform else {
      return result
    }
    let transformPoint = point.applying(transform)

    if CGRect(origin: .zero, size: CGSize(width: textureWidth, height: textureHeight)).contains(transformPoint) {
      result = transformPoint
    } else {
      print("Invalid point \(point) result point \(transformPoint)")
    }

    return result
  }

  func viewPointForTexture(point: CGPoint) -> CGPoint? {
    var result: CGPoint?
    guard let transform = textureTranform?.inverted() else {
      return result
    }
    let transformPoint = point.applying(transform)

    if internalBounds.contains(transformPoint) {
      result = transformPoint
    } else {
      print("Invalid point \(point) result point \(transformPoint)")
    }

    return result
  }

  func flushTextureCache() {
    textureCache = nil
  }

  private func setupTransform(width: Int, height: Int) {
    var scaleX: Float = 1.0
    var scaleY: Float = 1.0
    var resizeAspect: Float = 1.0

    internalBounds = self.bounds
    textureWidth = width
    textureHeight = height

    if textureWidth > 0 && textureHeight > 0 {
      scaleX = Float(internalBounds.width / CGFloat(textureWidth))
      scaleY = Float(internalBounds.height / CGFloat(textureHeight))
    }
    // Resize aspect ratio.
    resizeAspect = min(scaleX, scaleY)
    if scaleX < scaleY {
      scaleY = scaleX / scaleY
      scaleX = 1.0
    } else {
      scaleX = scaleY / scaleX
      scaleY = 1.0
    }

    // Vertex coordinate takes the gravity into account.
    let vertexData: [Float] = [
      -scaleX, -scaleY, 0.0, 1.0,
      scaleX, -scaleY, 0.0, 1.0,
      -scaleX, scaleY, 0.0, 1.0,
      scaleX, scaleY, 0.0, 1.0
    ]
    vertexCoordBuffer = device!.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: [])

    // Texture coordinate takes the rotation into account.
    let textData: [Float] = [
      0.0, 1.0,
      1.0, 1.0,
      0.0, 0.0,
      1.0, 0.0
    ]

    textCoordBuffer = device?.makeBuffer(bytes: textData, length: textData.count * MemoryLayout<Float>.size, options: [])

    // Calculate the transform from texture coordinates to view coordinates
    var transform = CGAffineTransform.identity
    transform = transform.concatenating(CGAffineTransform(rotationAngle: CGFloat(0)))

    transform = transform.concatenating(CGAffineTransform(scaleX: CGFloat(resizeAspect), y: CGFloat(resizeAspect)))
    let tranformRect = CGRect(origin: .zero, size: CGSize(width: textureWidth, height: textureHeight)).applying(transform)
    let xShift = (internalBounds.size.width - tranformRect.size.width) / 2
    let yShift = (internalBounds.size.height - tranformRect.size.height) / 2
    transform = transform.concatenating(CGAffineTransform(translationX: xShift, y: yShift))
    textureTranform = transform.inverted()
  }

  required init(coder: NSCoder) {
    super.init(coder: coder)
    device = MTLCreateSystemDefaultDevice()
    setUpMetal()
  }

  /// For a view made in code, like the second camera's preview.
  init() {
    super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
    setUpMetal()
  }

  private func setUpMetal() {
    configureMetal()

    createTextureCache()

    colorPixelFormat = .bgra8Unorm
  }

  func configureMetal() {
    let defaultLibrary = device!.makeDefaultLibrary()!
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipelineDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "vertexPassThrough")
    pipelineDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "fragmentPassThrough")

    // To determine how textures are sampled, create a sampler descriptor to query for a sampler state from the device.
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.sAddressMode = .clampToEdge
    samplerDescriptor.tAddressMode = .clampToEdge
    samplerDescriptor.minFilter = .linear
    samplerDescriptor.magFilter = .linear
    sampler = device!.makeSamplerState(descriptor: samplerDescriptor)

    do {
      renderPipelineState = try device!.makeRenderPipelineState(descriptor: pipelineDescriptor)
    } catch {
      fatalError("Unable to create preview Metal view pipeline state. (\(error))")
    }

    commandQueue = device!.makeCommandQueue()
  }

  func createTextureCache() {
    var newTextureCache: CVMetalTextureCache?
    if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device!, nil, &newTextureCache) == kCVReturnSuccess {
      textureCache = newTextureCache
    } else {
      // A runtime failure, not a programmer error. draw skips the frame and tries again on the next.
      print("Could not allocate the preview texture cache")
    }
  }

  /// - Tag: DrawMetalTexture
  override func draw(_ rect: CGRect) {
    var pixelBuffer: CVPixelBuffer?

    syncQueue.sync {
      pixelBuffer = internalPixelBuffer
    }

    guard let drawable = currentDrawable,
      let currentRenderPassDescriptor = currentRenderPassDescriptor,
      let previewPixelBuffer = pixelBuffer else {
        return
    }

    // Create a Metal texture from the image buffer.
    let width = CVPixelBufferGetWidth(previewPixelBuffer)
    let height = CVPixelBufferGetHeight(previewPixelBuffer)

    if textureCache == nil {
      createTextureCache()
    }
    // Still nothing means this frame can't be drawn. A preview that skips a frame is nothing;
    // handing CoreVideo a nil cache took the whole app down.
    guard let textureCache = textureCache else { return }
    var cvTextureOut: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                              textureCache,
                                              previewPixelBuffer,
                                              nil,
                                              .bgra8Unorm,
                                              width,
                                              height,
                                              0,
                                              &cvTextureOut)
    guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
      print("Failed to create preview texture")

      CVMetalTextureCacheFlush(textureCache, 0)
      return
    }

    if texture.width != textureWidth ||
      texture.height != textureHeight ||
      self.bounds != internalBounds {
      setupTransform(width: texture.width, height: texture.height)
    }

    // Set up command buffer and encoder
    guard let commandQueue = commandQueue else {
      print("Failed to create Metal command queue")
      CVMetalTextureCacheFlush(textureCache, 0)
      return
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      print("Failed to create Metal command buffer")
      CVMetalTextureCacheFlush(textureCache, 0)
      return
    }

    guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor) else {
      print("Failed to create Metal command encoder")
      CVMetalTextureCacheFlush(textureCache, 0)
      return
    }

    commandEncoder.label = "Preview display"
    commandEncoder.setRenderPipelineState(renderPipelineState!)
    commandEncoder.setVertexBuffer(vertexCoordBuffer, offset: 0, index: 0)
    commandEncoder.setVertexBuffer(textCoordBuffer, offset: 0, index: 1)
    commandEncoder.setFragmentTexture(texture, index: 0)
    commandEncoder.setFragmentSamplerState(sampler, index: 0)
    commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    commandEncoder.endEncoding()

    // Draw to the screen.
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}
