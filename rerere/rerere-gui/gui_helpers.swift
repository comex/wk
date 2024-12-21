import SwiftUI
struct WrappingLayout: Layout {
    // This seems like we'll call sizeThatFits so many times...
    typealias Cache = () // ...
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
        let width: CGFloat = bounds?.width ?? proposal.width ?? 200
        var yCur: CGFloat = 0
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        for subview in subviews {
            let proposal = ProposedViewSize(width: width, height: nil)
            let subSize = subview.sizeThatFits(proposal)
            //print("   xCur=\(xOffset) yCur=\(yOffset) subSize=\(subSize)")
            if subSize.width > width - xOffset {
                yOffset += yCur
                xOffset = 0
                yCur = 0
            }
            yCur = max(yCur, subSize.height)
            if let bounds {
                //print("   placing at (\(xOffset), \(yOffset))")
                subview.place(
                    at: CGPoint(x: bounds.minX + xOffset, y: bounds.minY + yOffset),
                    anchor: .topLeading,
                    proposal: proposal
                )
            }
            xOffset += subSize.width
        }
        yOffset += yCur
        return CGSize(width: width, height: yOffset)
    }
}

