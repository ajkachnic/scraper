pub type Document

pub type HtmlAttributes

pub type HtmlNode {
  Tag(String, HtmlAttributes, List(HtmlNode))
  Comment(String)
  Doctype(String, String, String)
  Declaration(String, HtmlAttributes)
  Text(String)
}

pub type HtmlTree =
  List(HtmlNode)

// pub type HtmlNode

// Parses an HTML document from a string
@external(erlang, "Elixir.Floki", "parse_document")
pub fn parse_document(html: String) -> Result(HtmlTree, String)

@external(erlang, "Elixir.Floki", "find")
pub fn find(html: HtmlTree, selector: String) -> HtmlNode

@external(erlang, "Elixir.Floki", "attribute")
pub fn attribute(html: HtmlNode, selector: String) -> List(String)
