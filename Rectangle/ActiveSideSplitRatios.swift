/// ActiveSideSplitRatios.swift

import Foundation

final class ActiveSideSplitRatios {

    static let shared = ActiveSideSplitRatios()

    private struct ScreenKey: Hashable {
        let minX: Int
        let minY: Int
        let width: Int
        let height: Int

        init(_ frame: CGRect) {
            minX = Self.keyPart(frame.minX)
            minY = Self.keyPart(frame.minY)
            width = Self.keyPart(frame.width)
            height = Self.keyPart(frame.height)
        }

        private static func keyPart(_ value: CGFloat) -> Int {
            Int(round(value * 1000.0))
        }
    }

    private struct SplitRatios {
        var horizontal: Float?
        var vertical: Float?
    }

    private var ratiosByScreen = [ScreenKey: SplitRatios]()
    private var configuredHorizontalPercent: Float
    private var configuredVerticalPercent: Float

    private init() {
        configuredHorizontalPercent = Defaults.horizontalSplitRatio.value
        configuredVerticalPercent = Defaults.verticalSplitRatio.value
    }

    func horizontalRatio(for screenFrame: CGRect) -> Float {
        resetChangedConfiguredDefaults()
        return ratiosByScreen[ScreenKey(screenFrame)]?.horizontal ?? configuredHorizontalRatio
    }

    func verticalRatio(for screenFrame: CGRect) -> Float {
        resetChangedConfiguredDefaults()
        return ratiosByScreen[ScreenKey(screenFrame)]?.vertical ?? configuredVerticalRatio
    }

    func recordSideAction(_ action: WindowAction, targetFrame: CGRect, screenFrame: CGRect) {
        resetChangedConfiguredDefaults()

        guard !targetFrame.isNull,
              !screenFrame.isNull,
              screenFrame.width > 0,
              screenFrame.height > 0
        else {
            return
        }

        switch action {
        case .leftHalf:
            setHorizontalRatio(Float(targetFrame.width / screenFrame.width), for: screenFrame)
        case .rightHalf:
            setHorizontalRatio(1.0 - Float(targetFrame.width / screenFrame.width), for: screenFrame)
        case .topHalf:
            setVerticalRatio(Float(targetFrame.height / screenFrame.height), for: screenFrame)
        case .bottomHalf:
            setVerticalRatio(1.0 - Float(targetFrame.height / screenFrame.height), for: screenFrame)
        default:
            return
        }
    }

    func recordAchievedCooperativeAction(_ action: WindowAction,
                                         achievedFrame: CGRect,
                                         screenFrame: CGRect,
                                         gapSize: CGFloat) {
        resetChangedConfiguredDefaults()

        guard !achievedFrame.isNull,
              !screenFrame.isNull,
              screenFrame.width > 0,
              screenFrame.height > 0
        else {
            return
        }

        // GapCalculation leaves half of the internal gap on each side of the raw split boundary.
        let halfGap = max(0, gapSize) / 2.0

        switch action {
        case .leftHalf:
            recordLeadingHorizontalBoundary(achievedFrame.maxX + halfGap, screenFrame: screenFrame)
        case .rightHalf:
            recordLeadingHorizontalBoundary(achievedFrame.minX - halfGap, screenFrame: screenFrame)
        case .topHalf:
            recordLeadingVerticalBoundary(achievedFrame.minY - halfGap, screenFrame: screenFrame)
        case .bottomHalf:
            recordLeadingVerticalBoundary(achievedFrame.maxY + halfGap, screenFrame: screenFrame)
        case .topLeft:
            recordLeadingHorizontalBoundary(achievedFrame.maxX + halfGap, screenFrame: screenFrame)
            recordLeadingVerticalBoundary(achievedFrame.minY - halfGap, screenFrame: screenFrame)
        case .topRight:
            recordLeadingHorizontalBoundary(achievedFrame.minX - halfGap, screenFrame: screenFrame)
            recordLeadingVerticalBoundary(achievedFrame.minY - halfGap, screenFrame: screenFrame)
        case .bottomLeft:
            recordLeadingHorizontalBoundary(achievedFrame.maxX + halfGap, screenFrame: screenFrame)
            recordLeadingVerticalBoundary(achievedFrame.maxY + halfGap, screenFrame: screenFrame)
        case .bottomRight:
            recordLeadingHorizontalBoundary(achievedFrame.minX - halfGap, screenFrame: screenFrame)
            recordLeadingVerticalBoundary(achievedFrame.maxY + halfGap, screenFrame: screenFrame)
        default:
            return
        }
    }

    func resetAll() {
        ratiosByScreen.removeAll()
        configuredHorizontalPercent = Defaults.horizontalSplitRatio.value
        configuredVerticalPercent = Defaults.verticalSplitRatio.value
    }

    func reset(for screenFrame: CGRect) {
        ratiosByScreen.removeValue(forKey: ScreenKey(screenFrame))
    }

    private var configuredHorizontalRatio: Float {
        normalized(Defaults.horizontalSplitRatio.value / 100.0)
    }

    private var configuredVerticalRatio: Float {
        normalized(Defaults.verticalSplitRatio.value / 100.0)
    }

    private func setHorizontalRatio(_ ratio: Float, for screenFrame: CGRect) {
        updateRatios(for: screenFrame) { splitRatios in
            splitRatios.horizontal = normalized(ratio)
        }
    }

    private func setVerticalRatio(_ ratio: Float, for screenFrame: CGRect) {
        updateRatios(for: screenFrame) { splitRatios in
            splitRatios.vertical = normalized(ratio)
        }
    }

    private func recordLeadingHorizontalBoundary(_ boundary: CGFloat, screenFrame: CGRect) {
        setHorizontalRatio(Float((boundary - screenFrame.minX) / screenFrame.width), for: screenFrame)
    }

    private func recordLeadingVerticalBoundary(_ boundary: CGFloat, screenFrame: CGRect) {
        setVerticalRatio(Float((screenFrame.maxY - boundary) / screenFrame.height), for: screenFrame)
    }

    private func updateRatios(for screenFrame: CGRect, update: (inout SplitRatios) -> Void) {
        let key = ScreenKey(screenFrame)
        var splitRatios = ratiosByScreen[key] ?? SplitRatios()
        update(&splitRatios)
        ratiosByScreen[key] = splitRatios
    }

    private func resetChangedConfiguredDefaults() {
        let currentHorizontalPercent = Defaults.horizontalSplitRatio.value
        let currentVerticalPercent = Defaults.verticalSplitRatio.value

        if abs(currentHorizontalPercent - configuredHorizontalPercent) > CycleSize.matchingTolerance {
            resetHorizontalRatios()
            configuredHorizontalPercent = currentHorizontalPercent
        }

        if abs(currentVerticalPercent - configuredVerticalPercent) > CycleSize.matchingTolerance {
            resetVerticalRatios()
            configuredVerticalPercent = currentVerticalPercent
        }
    }

    private func resetHorizontalRatios() {
        Array(ratiosByScreen.keys).forEach { key in
            ratiosByScreen[key]?.horizontal = nil
            removeEmptyRatios(for: key)
        }
    }

    private func resetVerticalRatios() {
        Array(ratiosByScreen.keys).forEach { key in
            ratiosByScreen[key]?.vertical = nil
            removeEmptyRatios(for: key)
        }
    }

    private func removeEmptyRatios(for key: ScreenKey) {
        if ratiosByScreen[key]?.horizontal == nil,
           ratiosByScreen[key]?.vertical == nil {
            ratiosByScreen.removeValue(forKey: key)
        }
    }

    private func normalized(_ ratio: Float) -> Float {
        min(1.0, max(0.0, ratio))
    }
}
