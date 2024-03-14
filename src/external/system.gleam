pub type TimeUnit {
  Second
  Millisecond
  Microsecond
  Nanoseocnd
  Native
}

@external(erlang, "erlang", "system_time")
pub fn system_time(unit: TimeUnit) -> Int
