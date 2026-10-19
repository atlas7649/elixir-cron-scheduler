defmodule CronyxTest do
  use ExUnit.Case

  alias Cronyx

  test "parses a valid expression" do
    assert {:ok, _cron} = Cronyx.parse("*/15 * * * *")
  end

  test "rejects an expression with the wrong field count" do
    assert {:error, :invalid_field_count} = Cronyx.parse("* * *")
  end

  test "rejects an invalid minute" do
    assert {:error, _reason} = Cronyx.parse("60 * * * *")
  end

  test "computes the next minute" do
    start = ~N[2024-01-01 00:00:00]
    assert {:ok, ~N[2024-01-01 00:01:00]} = Cronyx.next("* * * * *", start)
  end

  test "applies a step" do
    start = ~N[2024-01-01 00:00:00]
    assert {:ok, ~N[2024-01-01 00:15:00]} = Cronyx.next("*/15 * * * *", start)
  end

  test "supports month and weekday names" do
    start = ~N[2024-06-01 00:00:00]
    assert {:ok, ~N[2024-06-01 09:30:00]} = Cronyx.next("30 9 * Jun Sat", start)
  end

  test "matches day of month or day of week when both are restricted" do
    start = ~N[2024-01-01 00:00:00]
    assert {:ok, ~N[2024-01-05 00:00:00]} = Cronyx.next("0 0 15 * Fri", start)
  end

  test "finds a leap day" do
    start = ~N[2023-03-01 00:00:00]
    assert {:ok, ~N[2024-02-29 00:00:00]} = Cronyx.next("0 0 29 2 *", start)
  end

  test "reports whether a datetime matches" do
    assert Cronyx.matches?("*/15 * * * *", ~N[2024-01-01 00:15:00])
    refute Cronyx.matches?("*/15 * * * *", ~N[2024-01-01 00:16:00])
  end

  test "next_from_now returns a future time" do
    assert {:ok, datetime} = Cronyx.next_from_now("* * * * *")
    assert DateTime.compare(datetime, DateTime.utc_now()) in [:gt, :eq]
  end
end
