import SwiftUI
struct WrappingLayout: Layout {
    // This seems like we'll call sizeThatFits so many times...
    typealias Cache = () // ...
    let jitterSeed: Int?
    init(jitterSeed: Int? = nil) {
        self.jitterSeed = jitterSeed
    }
    
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let ret = placeImpl(in: nil, proposal: proposal, subviews: subviews)
        //print("sizeThatFits(\(proposal)) -> \(ret)")
        return ret
    }


    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        _ = placeImpl(in: bounds, proposal: proposal, subviews: subviews)
    }
    
    private func placeImpl(
        in bounds: CGRect?,
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> CGSize {
        //print("placeImpl bounds=\(String(describing: bounds))")
        var curJitterSeed: UInt32? = nil
        if let jitterSeed { curJitterSeed = UInt32(truncatingIfNeeded: jitterSeed) }
        let width: CGFloat = bounds?.width ?? proposal.width ?? 200
        var yCur: CGFloat = 0
        var xOffsets: [(Int, CGFloat)] = []
        var maxXRight: CGFloat = 0
        var xRight: CGFloat = 0
        var yOffset: CGFloat = 0
        let flushRow: () -> Void = {
            if let bounds {
                var leftPad: CGFloat = 0
                let maxLeftPad = width - xRight
                if var cur = curJitterSeed {
                    cur = (cur &* 134775813) &+ 1
                    leftPad = maxLeftPad * (CGFloat(cur) / 4294967296.0)
                    curJitterSeed = cur
                }
                for (subviewIdx, xOffset) in xOffsets {
                    //print("   placing at (\(xOffset), \(yOffset))")
                    subviews[subviewIdx].place(
                        at: CGPoint(x: bounds.minX + xOffset + leftPad, y: bounds.minY + yOffset),
                        anchor: .topLeading,
                        proposal: proposal
                    )
                }
            }
            maxXRight = max(maxXRight, xRight)
            xRight = 0
            xOffsets = []
            yOffset += yCur
            yCur = 0
        }
        
        for (subviewIdx, subview) in subviews.enumerated() {
            let proposal = ProposedViewSize(width: width, height: nil)
            let subSize = subview.sizeThatFits(proposal)
            //print("   xCur=\(xOffset) yCur=\(yOffset) subSize=\(subSize)")
            if subSize.width > width - xRight {
                flushRow()
            }
            yCur = max(yCur, subSize.height)
            xOffsets.append((subviewIdx, xRight))
            xRight += subSize.width
        }
        flushRow()
        return CGSize(width: maxXRight, height: yOffset)
    }
}


#Preview {
    struct WrappingLayoutTestView: View {
        var body: some View {
            WrappingLayout(jitterSeed: 42) {
                ForEach(0..<20) { i in
                    VStack {
                        Text("Hello \(1 << i)!")
                        .border(.pink)
                        .fixedSize()
                    }
                        .padding(5)
                }

            }.border(.blue)
            
        }
    }
    return WrappingLayoutTestView()
}
