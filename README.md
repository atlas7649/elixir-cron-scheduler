# Cronyx

Cronyx is a small Elixir library and command-line tool for parsing five-field
cron expressions and computing the next scheduled run time.

## Requirements

* Elixir 1.10 or newer

## Build

```sh
mix deps.get
mix escript.build
./cronyx "*/15 * * * *"
```

## Library usage

```elixir
{:ok, next} = Cronyx.next("*/15 * * * *", ~N[2024-01-01 00:00:00])
#=> {:ok, ~N[2024-01-01 00:15:00]}

Cronyx.matches?("0 9 * * Mon-Fri", ~N[2024-01-02 09:00:00])
#=> true

{:ok, next} = Cronyx.next_from_now("0 0 * * *")
```

`next/2` accepts both `NaiveDateTime` and `DateTime` values. `next_from_now/1`
uses the current UTC time.

## CLI usage

```sh
# Next run from now
./cronyx "*/15 * * * *"

# Next run after an explicit start time
./cronyx "0 9 * * Mon-Fri" "2024-01-01T00:00:00Z"
```

## Expression syntax

Each expression has five fields:

```text
minute hour day-of-month month day-of-week
```

Supported features:

* `*` and `?` wildcards
* ranges such as `1-5`
* lists such as `1,3,5`
* steps such as `*/2` and `1-10/2`
* month names such as `Jan` or `January`
* weekday names such as `Mon` or `Monday`
* weekday values `0` and `7` both mean Sunday

When both day-of-month and day-of-week are restricted, a date matches if
either field matches.

## Tests

```sh
mix test
```
