//
//  ContentView.swift
//  test_yohaku
//
//  Created by mi on 2026/09/12.
//

import SwiftUI
import Combine

#if os(iOS)
@preconcurrency import AVFoundation
import CoreImage
import UIKit

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var operationResult: OperationResult?
    @State private var strokePoints: [CGPoint] = []
    @State private var isTrackingGesture = false
    @State private var didRecognizeCircle = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ZStack {
                    if let image = camera.processedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black
                    }

                    if let message = camera.message {
                        ContentUnavailableView(
                            "カメラを使用できません",
                            systemImage: "camera.fill",
                            description: Text(message)
                        )
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                        .padding()
                    }

                    GestureOverlay(result: operationResult)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            handleGestureChanged(value)
                        }
                        .onEnded { value in
                            handleGestureEnded(value)
                        }
                )

                FilterControl(mode: camera.filterMode) {
                    camera.cycleFilter()
                }
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .onAppear {
            camera.start()
        }
    }

    private func handleGestureChanged(_ value: DragGesture.Value) {
        if !isTrackingGesture {
            isTrackingGesture = true
            didRecognizeCircle = false
            strokePoints = [value.startLocation]
            operationResult = nil
        }

        appendStrokePoint(value.location)
        guard GestureClassifier.pathLength(of: strokePoints) >= GestureThresholds.tapMovementDistance else {
            return
        }

        if !didRecognizeCircle {
            didRecognizeCircle = GestureClassifier.isCircle(strokePoints)
        }
        operationResult = .stroke(strokePoints, isCircle: didRecognizeCircle)
    }

    private func handleGestureEnded(_ value: DragGesture.Value) {
        guard isTrackingGesture else { return }
        appendStrokePoint(value.location)

        if GestureClassifier.pathLength(of: strokePoints) < GestureThresholds.tapMovementDistance {
            operationResult = .tap(value.startLocation)
        } else {
            if !didRecognizeCircle {
                didRecognizeCircle = GestureClassifier.isCircle(strokePoints)
            }
            operationResult = .stroke(strokePoints, isCircle: didRecognizeCircle)
        }

        isTrackingGesture = false
        strokePoints = []
    }

    private func appendStrokePoint(_ point: CGPoint) {
        guard let lastPoint = strokePoints.last else {
            strokePoints.append(point)
            return
        }
        guard GestureClassifier.distance(from: lastPoint, to: point) >= GestureThresholds.pointSamplingDistance else {
            return
        }
        strokePoints.append(point)
    }
}

private enum CameraFilterMode: CaseIterable {
    case original
    case grayscale
    case grayscaleEdge
    case grayscaleEdgeBlur
    case motionEdge
    case edgePersistence
    case blur
    case sepia

    var displayName: String {
        switch self {
        case .original:
            "Original"
        case .grayscale:
            "Grayscale"
        case .grayscaleEdge:
            "Edge"
        case .grayscaleEdgeBlur:
            "Grayscale + Edge + Blur"
        case .motionEdge:
            "Motion Edge"
        case .edgePersistence:
            "Edge Persistence"
        case .blur:
            "Blur"
        case .sepia:
            "Sepia"
        }
    }

    var next: Self {
        let modes = Self.allCases
        let nextIndex = (modes.firstIndex(of: self)! + 1) % modes.count
        return modes[nextIndex]
    }
}

private struct FilterControl: View {
    let mode: CameraFilterMode
    let action: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: action) {
                    Label(mode.displayName, systemImage: "camera.filters")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.72), in: Capsule())
                }
                .accessibilityLabel("画像フィルター: \(mode.displayName)")
                .accessibilityHint("タップすると次のフィルターへ切り替わります")
                Spacer()
            }
            Spacer()
        }
        .padding(.top, 48)
        .padding(.leading, 16)
    }
}

private enum OperationResult {
    case tap(CGPoint)
    case stroke([CGPoint], isCircle: Bool)
}

private enum GestureThresholds {
    static let pointSamplingDistance: CGFloat = 2
    static let tapMovementDistance: CGFloat = 12
    static let minimumCirclePathLength: CGFloat = 200
    static let maximumCircleClosureDistance: CGFloat = 45
    static let minimumCircleArea: CGFloat = 3_500
    static let minimumCircleDiameter: CGFloat = 70
    static let minimumCircleAspectRatio: CGFloat = 0.55
}

private enum GestureClassifier {
    static func isCircle(_ points: [CGPoint]) -> Bool {
        guard points.count >= 12,
              pathLength(of: points) >= GestureThresholds.minimumCirclePathLength,
              let first = points.first,
              let last = points.last,
              distance(from: first, to: last) <= GestureThresholds.maximumCircleClosureDistance else {
            return false
        }

        let xValues = points.map(\.x)
        let yValues = points.map(\.y)
        guard let minX = xValues.min(), let maxX = xValues.max(),
              let minY = yValues.min(), let maxY = yValues.max() else {
            return false
        }

        let width = maxX - minX
        let height = maxY - minY
        let aspectRatio = min(width, height) / max(width, height)
        guard min(width, height) >= GestureThresholds.minimumCircleDiameter,
              aspectRatio >= GestureThresholds.minimumCircleAspectRatio,
              enclosedArea(of: points) >= GestureThresholds.minimumCircleArea else {
            return false
        }
        return true
    }

    static func pathLength(of points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { length, pair in
            length + distance(from: pair.0, to: pair.1)
        }
    }

    static func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private static func enclosedArea(of points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        let pointsWithFirstAtEnd = Array(points.dropFirst()) + [points[0]]
        let area = zip(points, pointsWithFirstAtEnd).reduce(CGFloat.zero) { sum, pair in
            sum + (pair.0.x * pair.1.y) - (pair.1.x * pair.0.y)
        }
        return abs(area) / 2
    }
}

private struct GestureOverlay: View {
    let result: OperationResult?

    var body: some View {
        ZStack {
            Canvas { context, _ in
                guard let result else { return }
                switch result {
                case .tap(let point):
                    let markerSize: CGFloat = 12
                    let markerRect = CGRect(
                        x: point.x - markerSize / 2,
                        y: point.y - markerSize / 2,
                        width: markerSize,
                        height: markerSize
                    )
                    context.fill(Path(ellipseIn: markerRect), with: .color(.yellow))
                case .stroke(let points, let isCircle):
                    guard let firstPoint = points.first else { return }
                    var path = Path()
                    path.move(to: firstPoint)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    context.stroke(
                        path,
                        with: .color(isCircle ? .red : .blue),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                }
            }

            if case .some(.tap(let point)) = result {
                VStack {
                    Text("x: \(point.x, specifier: "%.1f"), y: \(point.y, specifier: "%.1f")")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.top, 16)
                    Spacer()
                }
            }
        }
    }
}

@MainActor
private final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var message: String?
    @Published private(set) var processedImage: UIImage?
    @Published private(set) var filterMode: CameraFilterMode = .original
    private var isConfigured = false
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private let sessionQueue = DispatchQueue(label: "jp.masaru.test-yohaku.camera-session")
    private var frameCount = 0
    private var previousLuminanceSamples: [UInt8]?
    private var smoothedMotion: CGFloat = 1
    private var visualMotion: CGFloat = 1
    private var edgeHistory: [CGImage] = []

    override init() {
        super.init()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndStartSession()
                    } else {
                        self.message = "設定でカメラへのアクセスを許可してください。"
                    }
                }
            }
        case .denied, .restricted:
            message = "設定でカメラへのアクセスを許可してください。"
        @unknown default:
            message = "カメラの状態を確認できません。"
        }
    }

    func cycleFilter() {
        filterMode = filterMode.next
        resetTemporalEffects()
    }

    private func configureAndStartSession() {
        guard !isConfigured else {
            startRunning()
            return
        }

        let didConfigure = configureSession()
        guard didConfigure else { return }

        isConfigured = true
        startRunning()
    }

    private func startRunning() {
        let session = session
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            message = "背面カメラを利用できません。"
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                message = "カメラ入力を追加できません。"
                return false
            }
            session.addInput(input)

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: .main)
            guard session.canAddOutput(videoOutput) else {
                message = "カメラ映像の出力を追加できません。"
                return false
            }
            session.addOutput(videoOutput)
            return true
        } catch {
            message = "カメラの起動に失敗しました。"
            return false
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCount += 1

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let filteredImage = applyFilter(to: sourceImage, pixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(filteredImage, from: filteredImage.extent) else {
            return
        }

        processedImage = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    private func applyFilter(to image: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage {
        switch filterMode {
        case .original:
            image
        case .grayscale:
            grayscale(image)
        case .grayscaleEdge:
            edgeImage(from: grayscale(image), intensity: 6, blurRadius: 0)
        case .grayscaleEdgeBlur:
            grayscaleEdgeBlurImage(from: image)
        case .motionEdge:
            motionEdgeImage(from: image, pixelBuffer: pixelBuffer)
        case .edgePersistence:
            edgePersistenceImage(from: image)
        case .blur:
            image.applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: 8]
            )
            .cropped(to: image.extent)
        case .sepia:
            image.applyingFilter(
                "CISepiaTone",
                parameters: [kCIInputIntensityKey: 0.9]
            )
        }
    }

    private func grayscale(_ image: CIImage) -> CIImage {
        image.applyingFilter(
            "CIColorControls",
            parameters: [kCIInputSaturationKey: 0]
        )
    }

    private func grayscaleEdgeBlurImage(from image: CIImage) -> CIImage {
        let grayscaleImage = grayscale(image)
        let edge = edgeImage(
            from: grayscaleImage,
            intensity: MotionEdgeSettings.baseEdgeIntensity,
            blurRadius: MotionEdgeSettings.baseEdgeBlurRadius
        )
        return composite(
            background: grayscaleImage,
            backgroundStrength: MotionEdgeSettings.baseBackgroundStrength,
            edge: edge,
            edgeStrength: MotionEdgeSettings.baseEdgeStrength
        )
    }

    private func motionEdgeImage(from image: CIImage, pixelBuffer: CVPixelBuffer) -> CIImage {
        let motion = updateMotion(using: pixelBuffer)
        let grayscaleImage = grayscale(image)
        let edge = edgeImage(
            from: grayscaleImage,
            intensity: MotionEdgeSettings.baseEdgeIntensity,
            blurRadius: interpolate(
                MotionEdgeSettings.stillEdgeBlurRadius,
                MotionEdgeSettings.movingEdgeBlurRadius,
                by: motion
            )
        )
        let temporallySmoothedEdge = edgeWithHistory(
            edge,
            maximumHistoryCount: 1,
            historyStrength: MotionEdgeSettings.motionEdgeHistoryStrength
        )
        return composite(
            background: grayscaleImage,
            backgroundStrength: interpolate(
                MotionEdgeSettings.stillBackgroundStrength,
                MotionEdgeSettings.movingBackgroundStrength,
                by: motion
            ),
            edge: temporallySmoothedEdge,
            edgeStrength: interpolate(
                MotionEdgeSettings.stillEdgeStrength,
                MotionEdgeSettings.movingEdgeStrength,
                by: motion
            )
        )
    }

    private func edgePersistenceImage(from image: CIImage) -> CIImage {
        let grayscaleImage = grayscale(image)
        let edge = edgeImage(
            from: grayscaleImage,
            intensity: MotionEdgeSettings.baseEdgeIntensity,
            blurRadius: MotionEdgeSettings.persistenceEdgeBlurRadius
        )
        let persistentEdge = edgeWithHistory(
            edge,
            maximumHistoryCount: MotionEdgeSettings.persistenceHistoryCount,
            historyStrength: MotionEdgeSettings.persistenceHistoryStrength
        )
        return composite(
            background: grayscaleImage,
            backgroundStrength: MotionEdgeSettings.persistenceBackgroundStrength,
            edge: persistentEdge,
            edgeStrength: MotionEdgeSettings.persistenceEdgeStrength
        )
    }

    private func edgeImage(from image: CIImage, intensity: CGFloat, blurRadius: CGFloat) -> CIImage {
        let edge = image.applyingFilter(
            "CIEdges",
            parameters: [kCIInputIntensityKey: intensity]
        )
        guard blurRadius > 0 else { return edge }
        return edge.applyingFilter(
            "CIGaussianBlur",
            parameters: [kCIInputRadiusKey: blurRadius]
        )
        .cropped(to: image.extent)
    }

    private func composite(
        background: CIImage,
        backgroundStrength: CGFloat,
        edge: CIImage,
        edgeStrength: CGFloat
    ) -> CIImage {
        scaledIntensity(edge, by: edgeStrength).applyingFilter(
            "CIAdditionCompositing",
            parameters: [kCIInputBackgroundImageKey: scaledIntensity(background, by: backgroundStrength)]
        )
    }

    private func scaledIntensity(_ image: CIImage, by amount: CGFloat) -> CIImage {
        image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ]
        )
    }

    private func updateMotion(using pixelBuffer: CVPixelBuffer) -> CGFloat {
        guard frameCount.isMultiple(of: MotionEdgeSettings.motionAnalysisFrameInterval),
              let samples = luminanceSamples(from: pixelBuffer) else {
            return visualMotion
        }

        defer { previousLuminanceSamples = samples }
        guard let previousLuminanceSamples else { return visualMotion }

        let meanDifference = zip(samples, previousLuminanceSamples).reduce(CGFloat.zero) { sum, pair in
            sum + abs(CGFloat(pair.0) - CGFloat(pair.1))
        } / CGFloat(samples.count * 255)
        let normalizedMotion = clamp(
            (meanDifference - MotionEdgeSettings.motionNoiseFloor) /
                (MotionEdgeSettings.motionFullScale - MotionEdgeSettings.motionNoiseFloor)
        )
        smoothedMotion += (normalizedMotion - smoothedMotion) * MotionEdgeSettings.motionSmoothing
        visualMotion += (smoothedMotion - visualMotion) * MotionEdgeSettings.visualSmoothing
        return visualMotion
    }

    private func luminanceSamples(from pixelBuffer: CVPixelBuffer) -> [UInt8]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        var samples: [UInt8] = []
        samples.reserveCapacity(MotionEdgeSettings.motionSampleColumns * MotionEdgeSettings.motionSampleRows)

        for sampleY in 0 ..< MotionEdgeSettings.motionSampleRows {
            let y = min(height - 1, sampleY * height / MotionEdgeSettings.motionSampleRows)
            for sampleX in 0 ..< MotionEdgeSettings.motionSampleColumns {
                let x = min(width - 1, sampleX * width / MotionEdgeSettings.motionSampleColumns)
                let offset = y * bytesPerRow + x * 4
                let blue = UInt16(pixels[offset])
                let green = UInt16(pixels[offset + 1])
                let red = UInt16(pixels[offset + 2])
                samples.append(UInt8((red * 77 + green * 150 + blue * 29) >> 8))
            }
        }
        return samples
    }

    private func edgeWithHistory(
        _ edge: CIImage,
        maximumHistoryCount: Int,
        historyStrength: CGFloat
    ) -> CIImage {
        var combinedEdge = edge
        for (index, historyImage) in edgeHistory.prefix(maximumHistoryCount).enumerated() {
            let decay = pow(MotionEdgeSettings.historyDecay, CGFloat(index + 1))
            let restoredEdge = CIImage(cgImage: historyImage)
                .transformed(by: CGAffineTransform(
                    scaleX: 1 / MotionEdgeSettings.historyImageScale,
                    y: 1 / MotionEdgeSettings.historyImageScale
                ))
                .cropped(to: edge.extent)
            combinedEdge = scaledIntensity(restoredEdge, by: historyStrength * decay)
                .applyingFilter(
                    "CIAdditionCompositing",
                    parameters: [kCIInputBackgroundImageKey: combinedEdge]
                )
        }

        storeEdgeInHistory(edge, maximumCount: maximumHistoryCount)
        return combinedEdge
    }

    private func storeEdgeInHistory(_ edge: CIImage, maximumCount: Int) {
        guard frameCount.isMultiple(of: MotionEdgeSettings.historyCaptureFrameInterval) else {
            return
        }

        let scaledExtent = edge.extent.applying(
            CGAffineTransform(
                scaleX: MotionEdgeSettings.historyImageScale,
                y: MotionEdgeSettings.historyImageScale
            )
        )
        let scaledEdge = edge.transformed(by: CGAffineTransform(
            scaleX: MotionEdgeSettings.historyImageScale,
            y: MotionEdgeSettings.historyImageScale
        ))
        .cropped(to: scaledExtent)
        guard let image = ciContext.createCGImage(scaledEdge, from: scaledExtent) else { return }

        edgeHistory.insert(image, at: 0)
        edgeHistory = Array(edgeHistory.prefix(maximumCount))
    }

    private func resetTemporalEffects() {
        frameCount = 0
        previousLuminanceSamples = nil
        smoothedMotion = 1
        visualMotion = 1
        edgeHistory = []
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, by amount: CGFloat) -> CGFloat {
        start + (end - start) * clamp(amount)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private enum MotionEdgeSettings {
    static let motionSampleColumns = 32
    static let motionSampleRows = 24
    static let motionAnalysisFrameInterval = 2
    static let motionNoiseFloor: CGFloat = 0.012
    static let motionFullScale: CGFloat = 0.10
    static let motionSmoothing: CGFloat = 0.18
    static let visualSmoothing: CGFloat = 0.08

    static let baseEdgeIntensity: CGFloat = 5
    static let baseBackgroundStrength: CGFloat = 0.55
    static let baseEdgeStrength: CGFloat = 0.75
    static let baseEdgeBlurRadius: CGFloat = 2.2

    static let stillBackgroundStrength: CGFloat = 0.16
    static let movingBackgroundStrength: CGFloat = 0.82
    static let stillEdgeStrength: CGFloat = 0.95
    static let movingEdgeStrength: CGFloat = 0.18
    static let stillEdgeBlurRadius: CGFloat = 0.8
    static let movingEdgeBlurRadius: CGFloat = 4.5
    static let motionEdgeHistoryStrength: CGFloat = 0.22

    static let persistenceBackgroundStrength: CGFloat = 0.28
    static let persistenceEdgeStrength: CGFloat = 0.72
    static let persistenceEdgeBlurRadius: CGFloat = 1.5
    static let persistenceHistoryCount = 4
    static let persistenceHistoryStrength: CGFloat = 0.28
    static let historyDecay: CGFloat = 0.62
    static let historyImageScale: CGFloat = 0.25
    static let historyCaptureFrameInterval = 3
}

#else

struct ContentView: View {
    var body: some View {
        ContentUnavailableView("この画面は iPhone で利用できます", systemImage: "camera.fill")
    }
}

#endif

#Preview {
    ContentView()
}
