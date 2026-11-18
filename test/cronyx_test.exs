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

  test "treats weekday 7 as Sunday" do
    start = ~N[2024-01-06 00:00:00]
    assert {:ok, ~N[2024-01-07 00:00:00]} = Cronyx.next("0 0 * * 7", start)
  end

  test "supports case-insensitive names" do
    assert {:ok, _cron} = Cronyx.parse("30 9 * JuN MoN")
  end

  test "computes a stepped range" do
    start = ~N[2024-01-01 00:00:00]
    assert {:ok, ~N[2024-01-01 00:01:00]} = Cronyx.next("1-10/3 * * * *", start)
  end

  test "rejects a descending range" do
    assert {:error, :invalid_field} = Cronyx.parse("5-1 * * * *")
  end

  test "reports no occurrence for an impossible date" do
    assert {:error, :no_occurrence_within_range} = Cronyx.next("0 0 31 2 *", ~N[2024-01-01 00:00:00])
  end

  test "valid? identifies valid and invalid expressions" do
    assert Cronyx.valid?("*/15 * * * *")
    refute Cronyx.valid?("not a cron")
  end

  test "computes multiple occurrences" do
    start = ~N[2024-01-01 00:00:00]

    assert {:ok,
            [
              ~N[2024-01-01 00:15:00],
              ~N[2024-01-01 00:30:00],
              ~N[2024-01-01 00:45:00]
            ]} = Cronyx.next_occurrences("*/15 * * * *", start, 3)
  end

  test "preserves an offset split across utc_offset and std_offset" do
    datetime = %DateTime{
      year: 2024,
      month: 1,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      time_zone: "Etc/UTC",
      utc_offset: 0,
      std_offset: 3600,
      zone_abbr: "+01:00",
      calendar: Calendar.ISO
    }

    assert {:ok, result} = Cronyx.next("*/15 * * * *", datetime)
    assert result.utc_offset == 0
    assert result.std_offset == 3600
  end

  test "preserves a regex fixed offset" do
    datetime = %DateTime{
      year: 2024,
      month: 1,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      time_zone: "+02:00",
      utc_offset: 7200,
      std_offset: 0,
      zone_abbr: "+02:00",
      calendar: Calendar.ISO
    }

    assert {:ok, result} = Cronyx.next("*/15 * * * *", datetime)
    assert result.time_zone == "+02:00"
    assert result.utc_offset == 7200
    assert result.std_offset == 0
  end

  test "valid? rejects non-binary input" do
    refute Cronyx.valid?(123)
  end

  test "next_from_now rejects non-binary input" do
    assert {:error, :invalid_expression} = Cronyx.next_from_now(123)
  end
end
