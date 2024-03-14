import external/floki
import gleam/http/response
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/otp/task
import gleam/result.{try}
import gleam/uri
import scraper/collector
import scraper/queue

fn handler(url: uri.Uri, res: response.Response(String)) {
  let assert Ok(tree) = floki.parse_document(res.body)
  // io.debug(tree)

  let links =
    tree
    |> floki.find("a[href]")
    |> floki.attribute("href")
    |> list.filter_map(fn(href) {
      use href <- try(uri.parse(href))

      case href {
        uri.Uri(scheme: Some(_), host: Some(_), ..) -> Ok(href)
        _ -> uri.merge(url, href)
      }
    })
    |> list.map(fn(l) { uri.to_string(l) })

  io.debug(links)
  Nil
}

pub fn main() {
  let collector =
    collector.new()
    |> collector.on_response(handler)

  use queue <- try(
    queue.start()
    |> result.replace_error(Nil),
  )

  use _ <- try(queue.add_url(queue, "https://bing.com"))
  use _ <- try(queue.add_url(queue, "https://google.com"))
  use _ <- try(queue.add_url(queue, "https://duckduckgo.com"))

  task.await_forever(queue.execute(
    collector: collector,
    queue: queue,
    workers: 5,
  ))

  Ok(Nil)
}
