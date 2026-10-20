defmodule Cronyx.CLI do
  @moduledoc false

  def main(argv) do
    case argv do
      [expression] ->
        run(expression, nil)

      [expression, datetime] ->
        run(expression, datetime)

      _ ->
        usage()
        System.halt(2)
    end
  end

  defp run(expression, datetime_string) do
    with {:ok, start} <- parse_start(datetime_string),
         {:ok, result} <- Cronyx.next(expression, start) do
      IO.puts(format(result))
    else
      {:error, :invalid_field_count} ->
        IO.puts(:stderr, "error: expected exactly five cron fields")
        System.halt(1)

      {:error, :empty_field} ->
        IO.puts(:stderr, "error: a cron field is empty")
        System.halt(1)

      {:error, :invalid_field} ->
        IO.puts(:stderr, "error: invalid cron field")
        System.halt(1)

      {:error, :no_occurrence_within_range} ->
        IO.puts(:stderr, "error: no matching time within five years")
        System.halt(1)

      {:error, _reason} ->
        IO.puts(:stderr, "error: invalid cron expression or datetime")
        System.halt(1)
    end
  end

  defp parse_start(nil) do
    {:ok, DateTime.utc_now()}
  end

  defp parse_start(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} ->
            case DateTime.from_naive(naive, "Etc/UTC") do
              {:ok, datetime} -> {:ok, datetime}
              {:ambiguous, datetime, _other} -> {:ok, datetime}
              {:gap, datetime, _other} -> {:ok, datetime}
              {:error, reason} -> {:error, reason}
            end

          {:error, _reason} ->
            {:error, :invalid_datetime}
        end
    end
  end

  defp format(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp usage do
    IO.puts(:stderr, "Usage: cronyx CRON_EXPRESSION [START_DATETIME]")
    IO.puts(:stderr, "Example: cronyx \"*/15 * * * *\" \"2024-01-01T00:00:00Z\"")
  end
end
