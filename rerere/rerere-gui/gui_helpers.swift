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
        print("sizeThatFits(\(proposal))")
        let ret = placeImpl(in: nil, proposal: proposal, subviews: subviews)
        print("    --> \(ret)")
        return ret
    }


    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        print("placeSubviews(in \(bounds), proposal: \(proposal))")
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
            let remHeight: CGFloat? = if let height = proposal.height {
                max(0, height - yOffset)
            } else { nil }

            let proposal = ProposedViewSize(width: width, height: remHeight)
            
            let subSize = subview.sizeThatFits(proposal)
            print("       subviews[\(subviewIdx)].sizeThatFits(\(proposal)) => \(subSize)")
            
            if subSize.width > width - xRight {
                flushRow()
            }
            yCur = max(yCur, subSize.height)
            xOffsets.append((subviewIdx, xRight))
            //print("   placing at (\(xRight), \(yOffset)) subSize=\(subSize)")
            
            xRight += subSize.width
        }
        flushRow()
        return CGSize(width: maxXRight, height: yOffset)
        
    }
}

// Test struct that wraps an existing layout just so we can log how it works
struct TestLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        ensure(subviews.count == 1)
        let ret = subviews[0].sizeThatFits(proposal)
        print("TV sizeThatFits(\(proposal)) --> \(ret)")
        return ret
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        print("TV placeSubviews(in \(bounds), proposal: \(proposal))")
        ensure(subviews.count == 1)
        subviews[0].place(at: bounds.origin, proposal: proposal)
        
    }
   
}


#Preview {
    struct WrappingLayoutTestView: View {
        var body: some View {
            WrappingLayout {
                ForEach(0..<5) { i in
                    VStack {
                        Text("Hello \(1 << i)!")
                        .border(.pink)
                    }
                        .padding(5)
                        
                }
                //Text("This is a very long piece of text asdf asdif oaisud oiaunsfdio uansdofu naosdufn oasdiufn oasudfno adsufno uasdnof uansdofu naosdufn oasdiufn aosdufn oaisudfn oausdfno iuadsnfo uasdnfo iuasndofiu asdf ")
                    //.frame(minWidth: 10, idealWidth: 40)
                    //.frame(width: 40)
                    
                    //.fixedSize()
            }
                .border(.blue)
                .frame(minWidth: 100, maxWidth: 800)
                //.containerRelativeFrame([.horizontal, .vertical])
                //.frame(width: 100)
                
                
        }
    }
    return WrappingLayoutTestView()
}
