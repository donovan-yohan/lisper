import AppKit
import MetalKit
import SwiftUI

struct LavaLampSurface: View {
    var pointer: CGPoint
    var intensity: Double
    var pointerInfluence: Double = 0

    var body: some View {
        LavaLampMetalSurface(pointer: pointer, intensity: intensity, pointerInfluence: pointerInfluence)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LavaLampMetalSurface: NSViewRepresentable {
    var pointer: CGPoint
    var intensity: Double
    var pointerInfluence: Double

    func makeNSView(context: Context) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let fallback = NSView()
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = NSColor.clear.cgColor
            return fallback
        }

        let view = LavaLampMetalView(frame: .zero, device: device)
        view.update(pointer: pointer, intensity: intensity, pointerInfluence: pointerInfluence)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? LavaLampMetalView)?.update(pointer: pointer, intensity: intensity, pointerInfluence: pointerInfluence)
    }
}

private final class LavaLampMetalView: MTKView {
    private let lavaRenderer: LavaLampRenderer

    init(frame: CGRect, device: MTLDevice) {
        lavaRenderer = LavaLampRenderer(device: device)
        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        wantsLayer = true
        layer?.isOpaque = false
        delegate = lavaRenderer
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        get { false }
        set {}
    }

    func update(pointer: CGPoint, intensity: Double, pointerInfluence: Double) {
        lavaRenderer.targetPointer = SIMD2<Float>(Float(pointer.x), Float(pointer.y))
        lavaRenderer.targetIntensity = Float(intensity)
        lavaRenderer.targetPointerInfluence = Float(pointerInfluence)
    }
}

private final class LavaLampRenderer: NSObject, MTKViewDelegate {
    var targetPointer = SIMD2<Float>(0.5, 0.5)
    var targetIntensity: Float = 1
    var targetPointerInfluence: Float = 0

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()
    private var pointer = SIMD2<Float>(0.5, 0.5)
    private var intensity: Float = 1
    private var pointerInfluence: Float = 0

    init(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue")
        }

        self.commandQueue = commandQueue

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexPassthrough")
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentLava")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Unable to compile lava lamp shader: \(error)")
        }

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        pointer = simd_mix(pointer, targetPointer, SIMD2<Float>(repeating: 0.18))
        intensity += (targetIntensity - intensity) * 0.12
        pointerInfluence += (targetPointerInfluence - pointerInfluence) * 0.16

        var uniforms: [Float] = [
            Float(CACurrentMediaTime() - startTime),
            Float(max(1, view.drawableSize.width)),
            Float(max(1, view.drawableSize.height)),
            pointer.x,
            pointer.y,
            intensity,
            pointerInfluence
        ]

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Float>.stride * uniforms.count, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vertexPassthrough(uint vertexID [[vertex_id]]) {
        float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        float2 uvs[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0)
        };

        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    static float2 rotate2d(float2 point, float angle) {
        float s = sin(angle);
        float c = cos(angle);
        return float2(c * point.x - s * point.y, s * point.x + c * point.y);
    }

    static float hash21(float2 point) {
        point = fract(point * float2(123.34, 456.21));
        point += dot(point, point + 45.32);
        return fract(point.x * point.y);
    }

    static float noise2d(float2 point) {
        float2 cell = floor(point);
        float2 local = fract(point);
        float2 curve = local * local * (3.0 - 2.0 * local);

        float a = hash21(cell);
        float b = hash21(cell + float2(1.0, 0.0));
        float c = hash21(cell + float2(0.0, 1.0));
        float d = hash21(cell + float2(1.0, 1.0));

        return mix(mix(a, b, curve.x), mix(c, d, curve.x), curve.y);
    }

    static float fbm(float2 point) {
        float value = 0.0;
        float amplitude = 0.5;

        for (int octave = 0; octave < 4; octave++) {
            value += amplitude * noise2d(point);
            point = rotate2d(point * 2.03 + float2(7.1, 3.9), 0.54);
            amplitude *= 0.5;
        }

        return value;
    }

    static float3 palette(float phase) {
        float roseMix = 0.5 + 0.5 * sin(6.28318 * phase);
        float blueMix = 0.5 + 0.5 * sin(6.28318 * (phase + 0.33));
        float3 pearl = float3(0.86, 0.91, 0.94);
        float3 rose = float3(0.95, 0.66, 0.88);
        float3 sky = float3(0.58, 0.84, 1.00);
        float3 lilac = float3(0.78, 0.70, 1.00);
        return mix(mix(rose, sky, blueMix), mix(pearl, lilac, roseMix), 0.42);
    }

    fragment float4 fragmentLava(VertexOut in [[stage_in]], constant float *uniforms [[buffer(0)]]) {
        float time = uniforms[0];
        float2 size = float2(uniforms[1], uniforms[2]);
        float2 pointer = float2(uniforms[3], uniforms[4]);
        float intensity = uniforms[5];
        float pointerInfluence = uniforms[6];

        float2 uv = in.uv;
        float aspect = size.x / max(size.y, 1.0);
        float2 cursor = (pointer - 0.5) * float2(aspect, 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0);
        float slowTime = time * 0.22;
        float cursorDistance = length(p - cursor);
        float cursorWarp = pointerInfluence * exp(-cursorDistance * 3.2);
        p += normalize(p - cursor + float2(0.001, -0.001)) * cursorWarp * 0.045;

        float3 centers[5] = {
            float3(0.34 + 0.18 * sin(slowTime * 0.91), 0.34 + 0.14 * cos(slowTime * 0.77), 0.24),
            float3(0.68 + 0.15 * cos(slowTime * 0.69), 0.42 + 0.20 * sin(slowTime * 0.61), 0.21),
            float3(0.52 + 0.20 * sin(slowTime * 0.47 + 1.7), 0.72 + 0.12 * cos(slowTime * 0.83), 0.25),
            float3(0.19 + 0.12 * cos(slowTime * 0.58 + 2.3), 0.72 + 0.18 * sin(slowTime * 0.74), 0.19),
            float3(0.81 + 0.10 * sin(slowTime * 0.52 + 4.1), 0.20 + 0.13 * cos(slowTime * 0.96), 0.17)
        };

        float field = 0.0;
        float shadePhase = 0.0;
        for (int index = 0; index < 5; index++) {
            float2 center = (centers[index].xy - 0.5) * float2(aspect, 1.0);
            float distanceToCenter = length(p - center);
            float radius = centers[index].z * (1.65 + intensity * 0.20);
            float blob = exp(-(distanceToCenter * distanceToCenter) / max(radius * radius, 0.001));
            field += blob * 0.24;
            shadePhase += blob * (0.09 + float(index) * 0.018);
        }

        float2 drift = float2(slowTime * 0.55, -slowTime * 0.42) + cursor * pointerInfluence * 0.18;
        float warpedNoise = fbm(p * 1.85 + drift);
        float fineNoise = fbm(rotate2d(p * (3.6 + pointerInfluence * 0.18), slowTime * 0.19));
        float ripples = sin((p.x * 2.2 - p.y * 1.8 + warpedNoise * 1.4 + slowTime) * 3.14159);

        float lava = smoothstep(0.38, 0.86, field + warpedNoise * 0.34 + ripples * 0.035);
        float phase = 0.58 + shadePhase + warpedNoise * 0.18 + fineNoise * 0.06 + slowTime * 0.055 + pointerInfluence * 0.025;

        float3 pearl = float3(0.70, 0.78, 0.82);
        float3 lavenderGlass = float3(0.74, 0.62, 0.86);
        float3 skyGlass = float3(0.56, 0.78, 0.88);
        float3 base = mix(pearl, mix(lavenderGlass, skyGlass, uv.x), 0.34);
        float3 iridescence = palette(phase);

        float edge = smoothstep(0.86, 0.20, length((uv - 0.5) * float2(1.02, 1.28)));
        float gloss = smoothstep(0.76, 0.12, length((uv - float2(0.22, 0.10)) * float2(1.0, 1.8)));
        float chroma = (0.18 + lava * 0.22 + pointerInfluence * 0.03) * intensity;

        float3 color = mix(base, iridescence, chroma);
        color += float3(0.38, 0.42, 0.48) * gloss * 0.18;
        color *= 0.98 + edge * 0.08;
        color += fineNoise * 0.010;

        float alpha = 0.42 + lava * 0.08;
        return float4(saturate(color), saturate(alpha));
    }
    """
}
