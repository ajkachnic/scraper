import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/iterator
import gleam/otp/actor
import gleam/otp/task
import gleam/result.{try}
import gleam/uri
import scraper/collector.{type Request}

pub type QueueState {
  QueueState(queue: List(Request))
}

pub type QueueMessage {
  // The `Push` message is used to add a new element to the stack.
  // It contains the item to add, the type of which is the `Request`
  // parameterised type.
  Push(Request)
  // The `Pop` message is used to remove an element from the stack.
  // It contains a `Subject`, which is used to send the response back to the
  // message sender. In this case the reply is of type `Result(Request, Nil)`.
  Pop(reply_with: Subject(Result(Request, Nil)))
}

pub type Queue =
  Subject(QueueMessage)

pub fn start() {
  actor.start(QueueState(queue: []), handle_message)
}

fn handle_message(
  message: QueueMessage,
  state: QueueState,
) -> actor.Next(QueueMessage, QueueState) {
  case message {
    // For the `Push` message we add the new element to the stack and return
    // `actor.continue` with this new stack, causing the actor to process any
    // queued messages or wait for more.
    Push(value) -> {
      let queue = [value, ..state.queue]
      actor.continue(QueueState(queue: queue))
    }
    // For the `Pop` message we attempt to remove an element from the stack,
    // sending it or an error back to the caller, before continuing.
    Pop(client) ->
      case state.queue {
        [] -> {
          actor.send(client, Error(Nil))
          actor.continue(state)
        }
        [first, ..rest] -> {
          actor.send(client, Ok(first))
          actor.continue(QueueState(queue: rest))
        }
      }
  }
}

/// Add a new URL to the queue
pub fn add_url(q: Queue, url: String) {
  use u <- try(uri.parse(url))
  let r = collector.from_uri(u)

  Ok(actor.send(q, Push(r)))
}

/// Pop a URL from the queue
pub fn pop(queue: Queue) {
  actor.call(queue, Pop, 50)
}

/// Starts async tasks and calls the Collector to perform.
/// requests. Returns a task that can be awaited with `task.await`
pub fn execute(
  collector collector: collector.Collector,
  queue queue: Queue,
  workers workers: Int,
) {
  // TODO: Use supervisor here
  task.async(fn() {
    iterator.repeatedly(fn() { task.async(fn() { worker(collector, queue) }) })
    |> iterator.map(task.await_forever)
    |> iterator.take(workers)
    |> iterator.to_list()
  })
}

/// Worker continously pops from the queue and makes requests.
fn worker(c: collector.Collector, queue: Queue) {
  case pop(queue) {
    Ok(request) -> {
      io.println("Scraping " <> uri.to_string(request.uri))
      // TODO: how do we handle error here? run a callback?
      let _ = case collector.scrape(c, request) {
        Ok(t) if c.timeout > 0 -> task.await(t, c.timeout)
        Ok(t) -> task.await_forever(t)
        Error(e) -> {
          // TODO: proper logging
          Error(io.debug(e))
        }
      }

      worker(c, queue)
    }
    Error(_) -> Nil
  }
}
