import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

pub type Status {
  Crawlable
  Uncrawlable
  Undefined
}

@external(erlang, "Elixir.Gollum", "crawlable?")
pub fn is_crawlable_ext(user_agent: String, url: String) -> Status

pub fn is_crawlable(user_agent: String, url: String) -> Bool {
  case is_crawlable_ext(user_agent, url) {
    Crawlable -> True
    _ -> False
  }
}

@external(erlang, "Elixir.Gollum.Cache", "start_link")
pub fn start_link(opts opts: List(#(String, Dynamic))) -> Result(Int, Dynamic)
