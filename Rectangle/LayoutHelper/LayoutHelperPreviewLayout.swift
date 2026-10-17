import Cocoa

struct LayoutHelperPreviewLayout {
    static let titleHeight: CGFloat = 40
    static let fallbackCardSize = CGSize(width: 200, height: 150)
    struct Result {
        let frames: [CGRect]
        let height: CGFloat
    }

    static func inset(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) / 8, min(size.width, size.height) < 320 ? 8 : 12)
    }

    static func sourceSize(for imageSize: CGSize?, fallback: CGSize) -> CGSize {
        guard let imageSize, imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return fallback }
        // Captures are scaled to whole pixels. Preserve the reserved geometry
        // when the difference is at most one captured pixel in either dimension.
        if fallback.width.isFinite, fallback.height.isFinite, fallback.width > 0, fallback.height > 0 {
            let fitted = max(imageSize.width / fallback.width, imageSize.height / fallback.height)
            if abs(imageSize.width - fallback.width * fitted) <= 1,
               abs(imageSize.height - fallback.height * fitted) <= 1 { return fallback }
        }
        // Use a genuinely changed aspect without making Retina captures larger cards.
        let extent = max(fallback.width, fallback.height)
        let scale = extent / max(imageSize.width, imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func cardFrame(for imageSize: CGSize?, in slot: CGRect, isMinimized: Bool = false) -> CGRect {
        guard let imageSize, imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              slot.width > 0, slot.height > titleHeight else { return slot }
        let fittedScale = min(slot.width / imageSize.width, (slot.height - titleHeight) / imageSize.height)
        // Width floors belong to the arrangement, which reserves both dimensions.
        // A preview must always fit until its updated aspect has been arranged.
        let scale = fittedScale
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale + titleHeight)
        return CGRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func arrange(sizes: [CGSize], in viewport: CGSize, compact: Bool = false,
                        expandedCards: [Bool] = []) -> Result {
        let width = max(1, viewport.width)
        let height = max(1, viewport.height)
        let gap: CGFloat = 16
        let sources = sizes.map { raw in
            raw.width.isFinite && raw.height.isFinite && raw.width > 0 && raw.height > 0
                ? raw : CGSize(width: 800, height: 500)
        }
        let floors = sources.indices.map { index -> CGSize in
            guard expandedCards.indices.contains(index), expandedCards[index] else { return .zero }
            let minimumWidth = min(fallbackCardSize.width, width)
            return CGSize(width: minimumWidth, height: compact ? fallbackCardSize.height - titleHeight
                          : minimumWidth * sources[index].height / sources[index].width)
        }
        let bases = sources.enumerated().map { index, source -> CGSize in
            let floor = floors[index]
            if compact { return CGSize(width: max(floor.width, min(180, width)), height: max(floor.height, 100)) }
            // Shared 36% scale, a readability floor for tiny windows, and a cap
            // prevent a huge source window from taking over the chooser.
            let scale = min(max(0.36, 120 / max(source.width, source.height)),
                            min(420, width) / source.width, 260 / source.height)
            return CGSize(width: max(floor.width, source.width * scale),
                          height: max(floor.height, source.height * scale))
        }
        func pack(_ scale: CGFloat) -> Result {
            var rows: [[CGSize]] = []
            var row: [CGSize] = []
            var used: CGFloat = 0
            for (index, base) in bases.enumerated() {
                let cardWidth = max(floors[index].width, base.width * scale)
                let imageHeight = compact ? max(floors[index].height, base.height * scale)
                    : cardWidth * base.height / base.width
                let size = CGSize(width: cardWidth, height: imageHeight + titleHeight)
                if !row.isEmpty && used + gap + size.width > width {
                    rows.append(row); row = []; used = 0
                }
                used += (row.isEmpty ? 0 : gap) + size.width
                row.append(size)
            }
            if !row.isEmpty { rows.append(row) }
            let rowHeights = rows.map { $0.map(\.height).max() ?? 0 }
            let total = rowHeights.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * gap
            var y = max(0, (height - total) / 2)
            var frames: [CGRect] = []
            for (index, row) in rows.enumerated() {
                let rowWidth = row.map(\.width).reduce(0, +) + CGFloat(row.count - 1) * gap
                var x = (width - rowWidth) / 2
                for size in row {
                    frames.append(CGRect(x: x, y: y + (rowHeights[index] - size.height) / 2,
                                         width: size.width, height: size.height))
                    x += size.width + gap
                }
                y += rowHeights[index] + gap
            }
            return Result(frames: frames, height: max(height, total))
        }
        // Stop shrinking at 60%, retaining the fallback-card floor. Overflow
        // scrolls instead of truncating short titles without a preview.
        for scale in [CGFloat(1), 0.9, 0.8, 0.7] {
            let result = pack(scale)
            if result.height <= height { return result }
        }
        return pack(0.6)
    }
}
