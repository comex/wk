class Superclass {
    init(withSuperclassDesignatedInit: ()) {
    }
    convenience init(withSuperclassConvenienceInit: ()) {
        self.init(withSuperclassDesignatedInit: ())
    }
}
class Subclass: Superclass {
    let foo: Int
    init(withSubclassDesignatedInit: ()) {
        self.foo = 42
        super.init(withSuperclassConvenienceInit: ())
    }
}
