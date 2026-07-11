import Foundation

/// Side-by-side layout for overlapping blocks, the same way Apple Calendar
/// renders conflicts: overlapping blocks form a cluster, each block gets a
/// column, and every block in the cluster is divided by the cluster's
/// column count.
enum BlockLayout {

    struct Placed: Identifiable {
        let block: TimeBlock
        let column: Int
        let columnCount: Int
        var id: String { block.id }
    }

    static func place(_ blocks: [TimeBlock], on day: Date) -> [Placed] {
        // Work in clamped day-local intervals so midnight-spanning events
        // cluster correctly.
        let items: [(block: TimeBlock, start: Date, end: Date)] = blocks
            .compactMap { block in
                guard let clamped = block.clamped(to: day) else { return nil }
                return (block, clamped.start, clamped.end)
            }
            .sorted { a, b in
                a.start != b.start ? a.start < b.start : a.end > b.end
            }

        var placed: [Placed] = []
        var clusterItems: [(block: TimeBlock, start: Date, end: Date, column: Int)] = []
        var columnEnds: [Date] = []   // per-column latest end within the cluster
        var clusterEnd = Date.distantPast

        func flushCluster() {
            guard !clusterItems.isEmpty else { return }
            let count = columnEnds.count
            for item in clusterItems {
                placed.append(Placed(block: item.block, column: item.column, columnCount: count))
            }
            clusterItems.removeAll()
            columnEnds.removeAll()
        }

        for item in items {
            if item.start >= clusterEnd {
                flushCluster()
                clusterEnd = item.end
            } else {
                clusterEnd = max(clusterEnd, item.end)
            }

            // Lowest column that has already ended.
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = item.end
                clusterItems.append((item.block, item.start, item.end, free))
            } else {
                columnEnds.append(item.end)
                clusterItems.append((item.block, item.start, item.end, columnEnds.count - 1))
            }
        }
        flushCluster()

        return placed
    }
}
