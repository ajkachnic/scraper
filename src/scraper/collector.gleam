import gleam/bit_array
import gleam/bool.{guard}
import gleam/crypto
import gleam/erlang/atom
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/otp/task
import gleam/result.{try}
import gleam/uri
// 
import scraper/store
import gets

pub type Request {
  Request(
    uri: uri.Uri,
    headers: List(http.Header),
    // The host header
    host: String,
    // Depth is the number of parents of the request
    depth: Int,
    method: http.Method,
    // Request body for POST/PUT
    body: String,
    // Unique identifier of the request
    id: Int,
  )
}

/// Construct a request from a URI.
pub fn from_uri(u: uri.Uri) {
  Request(
    uri: u,
    headers: [],
    host: "",
    depth: 0,
    method: http.Get,
    body: "",
    id: 0,
  )
}

pub fn to_http_request(r: Request) {
  use req <- try(request.from_uri(r.uri))

  Ok(
    req
    |> request.set_body(r.body)
    |> request.set_method(r.method)
    |> fn(x) { request.Request(..x, headers: r.headers) }
    |> request.set_header("Host", r.host),
  )
}

type ResponseHandler =
  fn(uri.Uri, response.Response(String)) -> Nil

pub type Collector {
  Collector(
    /// The User-Agent string used by HTTP requests
    user_agent: String,
    /// The recursion depth of visited URLs
    max_depth: Int,
    /// Domain whitelist.
    allowed_domains: List(String),
    /// Domain blocklist.
    disallowed_domains: List(String),
    /// The storage backend
    store: store.Store,
    on_response: ResponseHandler,
    // Request timeout in milliseconds
    timeout: Int,
  )
}

/// Create a new collector
pub fn new() {
  Collector(
    user_agent: "",
    max_depth: 10,
    allowed_domains: [],
    disallowed_domains: [],
    store: store.gets(atom.create_from_string("collector")),
    // event handlers
    on_response: fn(_, _) { Nil },
    timeout: -1,
  )
}

pub fn user_agent(c: Collector, user_agent: String) {
  Collector(..c, user_agent: user_agent)
}

pub fn on_response(c: Collector, handler: ResponseHandler) {
  Collector(..c, on_response: handler)
}

pub type ScrapeError {
  HttpError(hackney.Error)
  RequestError(RequestError)
  Other(Nil)
}

pub fn scrape(
  c: Collector,
  req: Request,
) -> Result(task.Task(Result(Nil, ScrapeError)), ScrapeError) {
  let uri = req.uri
  use _ <- try(
    request_check(c, req, True)
    |> result.map_error(RequestError(_)),
  )

  use req <- try(
    to_http_request(req)
    |> result.map_error(fn(_) { Other(Nil) }),
  )
  let req = request.set_header(req, "User-Agent", c.user_agent)

  Ok(task.async(fn() { fetch(c, uri, req) }))
}

fn fetch(c: Collector, url: uri.Uri, req: request.Request(String)) {
  let req = case request.get_header(req, "Accept") {
    Ok("") | Error(_) -> request.set_header(req, "Accept", "*/*")
    _ -> req
  }

  use response <- try(
    req
    |> hackney.send
    |> result.map_error(HttpError(_)),
  )

  c.on_response(url, response)

  Ok(Nil)
}

pub type RequestError {
  AlreadyVisited
  AtMaxDepth
  FailedToCheck
}

fn request_check(
  c: Collector,
  request: Request,
  check_revisit: Bool,
) -> Result(Nil, RequestError) {
  use <- guard(
    c.max_depth != 0 && c.max_depth < request.depth,
    Error(AtMaxDepth),
  )
  use <- guard(!check_revisit, Ok(Nil))

  let hash = request_hash(request.uri)
  use visited <- try(
    store.is_visited(c.store, hash)
    |> result.map_error(fn(_) { FailedToCheck }),
  )

  case visited {
    True -> Error(AlreadyVisited)
    False -> {
      case store.visited(c.store, hash) {
        Error(_) -> Error(FailedToCheck)
        Ok(_) -> Ok(Nil)
      }
    }
  }
}

fn request_hash(url: uri.Uri) -> BitArray {
  uri.to_string(url)
  |> bit_array.from_string()
  |> crypto.hash(crypto.Md5, _)
}
