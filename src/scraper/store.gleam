import gets
import gleam/bit_array
import gleam/erlang/atom
import gleam/erlang/process.{type Subject}
import gleam/result
import radish
import radish/client

type RedisClient =
  Subject(client.Message)

pub type Store {
  ETS(set: gets.Set(BitArray, Bool))
  Redis(client: RedisClient, timeout: Int, prefix: String)
}

/// Mark a site as visited
pub fn visited(store: Store, request_id: BitArray) -> Result(Store, Nil) {
  case store {
    ETS(visited) ->
      Ok(
        gets.insert(visited, request_id, True)
        |> ETS,
      )
    Redis(client, timeout, prefix) -> {
      get_id(prefix, request_id)
      |> radish.set(client, _, "1", timeout)
      |> result.nil_error
      |> result.map(fn(_) { Redis(client, timeout, prefix) })
    }
  }
}

/// Check if a site has already been visited
/// 
/// In the future, this could use some kind of cache invalidation
/// strategy so that we refetch sites after a period of time
pub fn is_visited(store: Store, request_id: BitArray) -> Result(Bool, Nil) {
  case store {
    ETS(visited) -> {
      case gets.lookup(visited, request_id) {
        Ok(_) -> Ok(True)
        Error(_) -> Ok(False)
      }
    }
    Redis(client, timeout, prefix) -> {
      // if the ID has been visited, it's in the database
      get_id(prefix, request_id)
      |> radish.get(client, _, timeout)
      |> result.map(fn(_) { True })
      |> result.nil_error
    }
  }
}

pub fn gets(name: atom.Atom) -> Store {
  ETS(set: gets.new(name))
}

fn get_id(prefix: String, id: BitArray) {
  prefix <> ":request:" <> bit_array.base64_encode(id, False)
}
