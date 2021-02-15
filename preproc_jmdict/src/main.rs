fn child_elms<'a, 'input: 'a>(node: &roxmltree::Node<'a, 'input>) -> impl Iterator<Item=roxmltree::Node<'a, 'input>> {
    node.children().filter(|child| child.is_element())
}
fn main() {
    let text = std::fs::read_to_string("../JMdict_e").unwrap();
    let doc = roxmltree::Document::parse_with_options(&text,
        roxmltree::ParsingOptions { allow_dtd: true, ..roxmltree::ParsingOptions::default() })
        .unwrap();
    let root_elm = doc.root().first_element_child().unwrap();
    assert!(root_elm.has_tag_name("JMdict"));
    for entry in child_elms(&root_elm) {
        println!("{:?}", entry);
        assert!(entry.has_tag_name("entry"));

    }
}
