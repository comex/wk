// based on https://github.com/autozimu/StringMetric.swift/blob/master/Sources/StringMetric.swift
// (which is wrong)
struct Levenshtein {
    // The previous row of distances
    var v0: [Int] = []
    // Current row of distances.
    var v1: [Int] = []

    public mutating func distance(between sourceString: String, and targetString: String) -> Int {
        if sourceString == targetString {
            return 0
        }
        let source = sourceString.utf8
        let target = targetString.utf8
        if source.count == 0 {
            return target.count
        }
        if target.count == 0 {
            return source.count
        }

        if v0.count < target.count + 1 {
            v0 = [Int](repeating: 0, count: target.count + 1)
            v1 = [Int](repeating: 0, count: target.count + 1)
        }
        // Initialize v0.
        // Edit distance for empty source.
        for i in 0..<target.count + 1 {
            v0[i] = i
        }

        var sourceI = source.startIndex
        for i in 0..<source.count {
            // Calculate v1 (current row distances) from previous row v0
            // Edit distance is delete (i + 1) chars from source to match empty t.
            v1[0] = i + 1

            // Use formula to fill rest of the row.
            var targetJ = source.startIndex
            for j in 0..<target.count {
                let cost = source[sourceI] == target[targetJ] ? 0 : 1
                v1[j + 1] = Swift.min(
                    v1[j] + 1,
                    v0[j + 1] + 1,
                    v0[j] + cost
                )
                target.formIndex(after: &targetJ)
            }

            // Copy current row to previous row for next iteration.
            swap(&v1, &v0)
            source.formIndex(after: &sourceI)
        }

        return v0[target.count]
    }

 }


