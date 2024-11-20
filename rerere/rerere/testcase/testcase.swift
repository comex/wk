import Foundation
func isSpace(_ c: UTF8.CodeUnit) -> Bool {
    c == 10
}
func trim(_ s: String) -> String {
    let a = s.utf8
    guard let start = a.firstIndex(where: { isSpace($0) }) else {
        return ""
    }
    let end = a.lastIndex(where: { isSpace($0) })!
    if a.index(after: end) == a.endIndex {
        return s
    } else {
        return String(a[...])!
    }
}
class Item: Comparable {
    let name: String
    let birthday: Date?
    let id: Int
    init(name: String, birthday: Date?) {
        self.name = name
        self.birthday = birthday
        id = 9
    }
    convenience init(name: String, from dec: Decoder) throws {
        enum K: CodingKey { case birth }
        let container = try dec.container(keyedBy: K.self)
        self.init(name: name,
                  birthday: try container.decodeIfPresent(Date.self, forKey: .birth))
    }
    static func == (lhs: Item, rhs: Item) -> Bool {
        lhs === rhs
    }
    static func < (lhs: Item, rhs: Item) -> Bool {
        lhs.id < rhs.id
    }
}
enum IngType{
    case primary}
struct Ing {
    let text: String
    let type: IngType
    let acceptedAnswerWK: Bool
    init(from dec: Decoder, isMeaning: Bool, relaxed: Bool) throws {
        do {
            let text = try dec.singleValueContainer().decode(String.self)
            self.text = text
            type = .primary
            acceptedAnswerWK = true
        }
    }
}
func decodeArray<T>(_ : UnkeyedDecodingContainer, callback: (Decoder) throws -> T) -> [T] {
    var ret: [T] = []
    return ret
}
struct Relaxed { let relaxed: Bool }
class NormalItem: Item{
    let meanings: [Ing]
    let readings: [Ing]
    let character: String
    required convenience init(from dec: Decoder) throws {
        try self.init(from: dec)
    }
    required init(from dec: Decoder, configuration: Relaxed) throws {
        let relaxed = configuration.relaxed
        enum K: CodingKey { case data, characters, readings, meanings}
        let topC = try dec.container(keyedBy: K.self)
        var dataC: KeyedDecodingContainer<K>
        if topC.contains(.data) {
            dataC = try topC} else {
            dataC = topC
        }
        character = (try dataC.decode(String.self, forKey: .characters))
        readings = try decodeArray(dataC.nestedUnkeyedContainer(forKey: .readings)) {
            try Ing(from: $0, isMeaning: false, relaxed: relaxed)
        }
        var meanings = try decodeArray(dataC.nestedUnkeyedContainer(forKey: .meanings)) {
            try Ing(from: $0, isMeaning: true, relaxed: relaxed)
        }
        self.meanings = meanings
        try super.init(name: character, from: dataC.superDecoder())
    }
}
