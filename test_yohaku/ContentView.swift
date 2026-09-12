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
    case blur
    case sepia

    var displayName: String {
        switch self {
        case .original:
            "Original"
        case .grayscale:
            "Grayscale"
        case .grayscaleEdge:
            "Grayscale + Edge"
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

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let filteredImage = applyFilter(to: sourceImage)
        guard let cgImage = ciContext.createCGImage(filteredImage, from: filteredImage.extent) else {
            return
        }

        processedImage = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    private func applyFilter(to image: CIImage) -> CIImage {
        switch filterMode {
        case .original:
            image
        case .grayscale:
            grayscale(image)
        case .grayscaleEdge:
            grayscale(image).applyingFilter(
                "CIEdges",
                parameters: [kCIInputIntensityKey: 6]
            )
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
