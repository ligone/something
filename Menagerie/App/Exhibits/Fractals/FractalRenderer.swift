import FractalKit
import Metal
import MetalKit
import QuartzCore

/// The Metal objects shared by every fractal view: compiled once per launch.
@MainActor
final class FractalGPU {
    static let shared: Result<FractalGPU, Error> = Result { try FractalGPU() }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let fractalPipeline: MTLRenderPipelineState
    let compositePipeline: MTLRenderPipelineState
    let pixelFormat: MTLPixelFormat = .bgra8Unorm

    struct SetupError: LocalizedError {
        let errorDescription: String?
    }

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SetupError(errorDescription: "This Mac has no Metal-capable GPU.")
        }
        guard let queue = device.makeCommandQueue() else {
            throw SetupError(errorDescription: "Could not create a Metal command queue.")
        }
        let options = MTLCompileOptions()
        // Double-float arithmetic relies on exact IEEE rounding; fast math
        // would "simplify" the error terms to zero.
        options.fastMathEnabled = false
        let library = try device.makeLibrary(source: FractalShaders.source, options: options)

        func pipeline(fragment: String, blending: Bool) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fractal_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            if blending {
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        self.device = device
        self.queue = queue
        fractalPipeline = try pipeline(fragment: "fractal_fragment", blending: true)
        compositePipeline = try pipeline(fragment: "composite_fragment", blending: false)
    }
}

/// Mirrors `FractalUniforms` in the shader. Scalars only, so the layouts match.
struct FractalUniforms {
    var centerXHi: Float = 0
    var centerXLo: Float = 0
    var centerYHi: Float = 0
    var centerYLo: Float = 0
    var juliaXHi: Float = 0
    var juliaXLo: Float = 0
    var juliaYHi: Float = 0
    var juliaYLo: Float = 0
    var scale: Float = 0
    var width: Float = 0
    var height: Float = 0
    var originX: Float = 0
    var originY: Float = 0
    var colorDensity: Float = 0
    var colorOffset: Float = 0
    var cornerRadius: Float = 0
    var interiorR: Float = 0
    var interiorG: Float = 0
    var interiorB: Float = 0
    var maxIterations: Int32 = 0
    var isJulia: Int32 = 0
    var precise: Int32 = 0
    var samplesPerAxis: Int32 = 1
}

/// Draws the model into an `MTKView`.
///
/// The main image is rendered into an offscreen texture only when something
/// that affects it changes. Every other frame just composites that texture
/// and the Julia inset, so hovering is cheap even at ten-billion-fold zoom.
/// While the user interacts, deep views render at half resolution; once they
/// settle, a full-resolution (and, for shallow views, supersampled) pass
/// replaces the draft.
@MainActor
final class FractalRenderer: NSObject, MTKViewDelegate {
    private let gpu: FractalGPU
    private let model: FractalModel

    private var mainTexture: MTLTexture?
    private var paletteTexture: MTLTexture?
    private var paletteName: String?
    private var lastMainUniforms: FractalUniforms?
    private var lastInsetUniforms: FractalUniforms?
    private var framesInFlight = 0

    init(gpu: FractalGPU, model: FractalModel) {
        self.gpu = gpu
        self.model = model
        super.init()
    }

    func configure(_ view: MTKView) {
        view.device = gpu.device
        view.colorPixelFormat = gpu.pixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = self
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            render(in: view)
        }
    }

    private func render(in view: MTKView) {
        let now = CACurrentMediaTime()
        model.layout(size: view.bounds.size)
        model.advance(to: now)

        // Never queue up work behind a slow frame: skip this tick instead.
        guard framesInFlight == 0 else { return }

        let size = view.bounds.size
        guard size.width >= 2, size.height >= 2 else { return }
        let backing = view.window?.backingScaleFactor ?? 2
        let interacting = model.isInteracting(now: now)

        // Decide how precise the arithmetic must be, then how many pixels we
        // can afford at that precision.
        let fullScale = model.viewport.scale / Double(backing)
        let precise = fullScale < FractalModel.precisionThreshold
        let resolution: CGFloat = (precise && interacting) ? 0.5 : 1
        let samples = (!precise && !interacting && model.antialiasing) ? 2 : 1

        // The drawable always matches the window's pixels, so resizing it
        // never races the frames in flight. Only the fractal itself drops to
        // a draft resolution; the composite pass scales it up to fit.
        let screenSize = CGSize(
            width: (size.width * backing).rounded(),
            height: (size.height * backing).rounded()
        )
        if view.drawableSize != screenSize {
            view.drawableSize = screenSize
        }
        let pixelSize = CGSize(
            width: (size.width * backing * resolution).rounded(),
            height: (size.height * backing * resolution).rounded()
        )
        let pixelsPerPoint = Double(backing * resolution)
        let screenPixelsPerPoint = Double(backing)

        var main = uniforms(
            viewport: model.viewport,
            kind: model.kind,
            pixelsPerPoint: pixelsPerPoint,
            size: pixelSize,
            precise: precise,
            samples: samples
        )
        main.maxIterations = Int32(model.iterationBudget)

        var inset: FractalUniforms?
        if let c = model.juliaPreviewParameter {
            let rect = model.juliaInsetRect
            let insetViewport = ComplexViewport.home(
                for: .julia(re: c.re, im: c.im), width: Double(rect.width), height: Double(rect.height)
            )
            var u = uniforms(
                viewport: insetViewport,
                kind: .julia(re: c.re, im: c.im),
                pixelsPerPoint: screenPixelsPerPoint,
                size: CGSize(width: rect.width * backing, height: rect.height * backing),
                precise: false,
                samples: interacting ? 1 : 2
            )
            u.originX = Float(rect.minX * backing)
            u.originY = Float(rect.minY * backing)
            u.cornerRadius = Float(14 * screenPixelsPerPoint)
            u.maxIterations = 300
            inset = u
        }

        let needsMain = mainTexture == nil
            || mainTexture?.width != Int(pixelSize.width)
            || mainTexture?.height != Int(pixelSize.height)
            || lastMainUniforms.map { !Self.same($0, main) } ?? true
        let needsPresent = needsMain || !Self.same(lastInsetUniforms, inset)
        guard needsPresent else { return }

        updatePaletteTexture()
        guard let paletteTexture,
              let drawable = view.currentDrawable,
              let commandBuffer = gpu.queue.makeCommandBuffer() else { return }

        if needsMain {
            guard let texture = ensureMainTexture(size: pixelSize) else { return }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                encoder.setRenderPipelineState(gpu.fractalPipeline)
                encoder.setFragmentBytes(&main, length: MemoryLayout<FractalUniforms>.stride, index: 0)
                encoder.setFragmentTexture(paletteTexture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
        }

        let screen = MTLRenderPassDescriptor()
        screen.colorAttachments[0].texture = drawable.texture
        screen.colorAttachments[0].loadAction = .dontCare
        screen.colorAttachments[0].storeAction = .store
        // Size everything on screen by the drawable actually handed out,
        // which can briefly lag a change to drawableSize.
        let target = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: screen), let mainTexture {
            encoder.setRenderPipelineState(gpu.compositePipeline)
            encoder.setFragmentTexture(mainTexture, index: 0)
            var targetSize = SIMD2<Float>(Float(target.width), Float(target.height))
            encoder.setFragmentBytes(&targetSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            if var inset {
                let x = Double(inset.originX)
                let y = Double(inset.originY)
                let w = Double(inset.width)
                let h = Double(inset.height)
                encoder.setViewport(MTLViewport(originX: x, originY: y, width: w, height: h, znear: 0, zfar: 1))
                encoder.setScissorRect(Self.scissor(x: x, y: y, width: w, height: h, limit: target))
                encoder.setRenderPipelineState(gpu.fractalPipeline)
                encoder.setFragmentBytes(&inset, length: MemoryLayout<FractalUniforms>.stride, index: 0)
                encoder.setFragmentTexture(paletteTexture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        framesInFlight += 1
        let iterations = Int(main.maxIterations)
        let model = self.model
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let seconds = buffer.gpuEndTime - buffer.gpuStartTime
            Task { @MainActor in
                self?.framesInFlight -= 1
                if needsMain {
                    model.recordFrame(gpuSeconds: seconds, iterations: iterations, precise: precise, pixels: pixelSize)
                }
            }
        }
        commandBuffer.commit()

        if needsMain { lastMainUniforms = main }
        lastInsetUniforms = inset
    }

    // MARK: Helpers

    private func uniforms(
        viewport: ComplexViewport,
        kind: FractalKind,
        pixelsPerPoint: Double,
        size: CGSize,
        precise: Bool,
        samples: Int
    ) -> FractalUniforms {
        let centerX = DoubleFloat(viewport.centerX)
        let centerY = DoubleFloat(viewport.centerY)
        var u = FractalUniforms()
        u.centerXHi = centerX.hi
        u.centerXLo = centerX.lo
        u.centerYHi = centerY.hi
        u.centerYLo = centerY.lo
        if case let .julia(re, im) = kind {
            let cx = DoubleFloat(re)
            let cy = DoubleFloat(im)
            u.juliaXHi = cx.hi
            u.juliaXLo = cx.lo
            u.juliaYHi = cy.hi
            u.juliaYLo = cy.lo
            u.isJulia = 1
        }
        u.scale = Float(viewport.scale / pixelsPerPoint)
        u.width = Float(size.width)
        u.height = Float(size.height)
        u.colorDensity = Float(model.colorDensity)
        u.colorOffset = Float(model.colorOffset)
        u.interiorR = Float(model.palette.interior.red)
        u.interiorG = Float(model.palette.interior.green)
        u.interiorB = Float(model.palette.interior.blue)
        u.precise = precise ? 1 : 0
        u.samplesPerAxis = Int32(samples)
        return u
    }

    private func ensureMainTexture(size: CGSize) -> MTLTexture? {
        let width = Int(size.width)
        let height = Int(size.height)
        if let mainTexture, mainTexture.width == width, mainTexture.height == height {
            return mainTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: gpu.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        mainTexture = gpu.device.makeTexture(descriptor: descriptor)
        return mainTexture
    }

    private func updatePaletteTexture() {
        guard paletteName != model.palette.name || paletteTexture == nil else { return }
        let count = 1024
        let bytes = model.palette.rgba8(count: count)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: count, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = gpu.device.makeTexture(descriptor: descriptor) else { return }
        bytes.withUnsafeBytes { buffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, count, 1),
                mipmapLevel: 0,
                withBytes: buffer.baseAddress!,
                bytesPerRow: count * 4
            )
        }
        paletteTexture = texture
        paletteName = model.palette.name
    }

    private static func scissor(x: Double, y: Double, width: Double, height: Double, limit: CGSize) -> MTLScissorRect {
        let x0 = max(0, min(Int(x), Int(limit.width)))
        let y0 = max(0, min(Int(y), Int(limit.height)))
        let x1 = max(x0, min(Int((x + width).rounded(.up)), Int(limit.width)))
        let y1 = max(y0, min(Int((y + height).rounded(.up)), Int(limit.height)))
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private static func same(_ a: FractalUniforms?, _ b: FractalUniforms?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?):
            return withUnsafeBytes(of: a) { lhs in
                withUnsafeBytes(of: b) { rhs in lhs.elementsEqual(rhs) }
            }
        default: return false
        }
    }
}
