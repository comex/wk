use std::str::FromStr;
fn child_elms<'a, 'input: 'a>(node: &roxmltree::Node<'a, 'input>) -> impl Iterator<Item=roxmltree::Node<'a, 'input>> {
    node.children().filter(|child| child.is_element())
}
fn children_named<'b, 'a: 'b, 'input: 'a>(node: &'b roxmltree::Node<'a, 'input>, name: &'b str) -> impl Iterator<Item=roxmltree::Node<'a, 'input>> + 'b {
    node.children().filter(move |child| child.tag_name().name() == name)
}
fn child_named<'a, 'input: 'a>(node: &roxmltree::Node<'a, 'input>, name: &str) -> roxmltree::Node<'a, 'input> {
    let mut children = children_named(node, name);
    let child = children.next().unwrap();
    assert!(children.next().is_none());
    child
}
fn main() {
    let text = std::fs::read_to_string("../JMdict_e").unwrap();
    let doc = roxmltree::Document::parse_with_options(&text,
        roxmltree::ParsingOptions { allow_dtd: true, ..roxmltree::ParsingOptions::default() })
        .unwrap();
    let root_elm = doc.root().first_element_child().unwrap();
    assert!(root_elm.has_tag_name("JMdict"));
    for entry in child_elms(&root_elm) {
        assert!(entry.has_tag_name("entry"));
        println!("{:?}", entry);
        let ent_seq = u64::from_str(child_named(&entry, "ent_seq").text().unwrap()).unwrap();
        let glosses: Vec<&str> = children_named(&entry, "sense").flat_map(|sense| -> Vec<roxmltree::Node> { children_named(&sense, "gloss").collect() }).map(|gloss| gloss.text().unwrap()).collect();
        let glosses_semi = glosses.join("; ");
        let posses: Vec<&str> = children_named(&entry, "sense").flat_map(|sense| -> Vec<roxmltree::Node> { children_named(&sense, "pos").collect() }).map(|pos| pos.text().unwrap()).collect();
        println!("{:?}", posses);
    }
}
