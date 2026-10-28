defmodule Cronyx do
  @moduledoc """
  Cronyx parses five-field cron expressions and computes the next run time.

  Supported syntax:

    * minute (0-59)
    * hour (0-23)
    * day of month (1-31)
    * month (1-12 or Jan-Dec)
    * day of week (0-7, where 0 and 7 are Sunday, or Sun-Sat)

  Fields may contain `*`, `?`, numbers, ranges (`1-5`), lists (`1,3,5`),
  and steps (`*/2`, `1-10/2`). When both day-of-month and day-of-week are
  restricted, a date matches if either matches, following common cron
  semantics.
  """

  defstruct [:minutes, :hours, :dom, :months, :dow, :dom_restricted, :dow_restricted]

  @month_names %{
    "jan" => 1,
    "january" => 1,
    "feb" => 2,
    "february" => 2,
    "mar" => 3,
    "march" => 3,
    "apr" => 4,
    "april" => 4,
    "may" => 5,
    "jun" => 6,
    "june" => 6,
    "jul" => 7,
    "july" => 7,
    "aug" => 8,
    "august" => 8,
    "sep" => 9,
    "september" => 9,
    "oct" => 10,
    "october" => 10,
    "nov" => 11,
    "november" => 11,
    "dec" => 12,
    "december" => 12
  }

  @day_names %{
    "sun" => 0,
    "sunday" => 0,
    "mon" => 1,
    "monday" => 1,
    "tue" => 2,
    "tuesday" => 2,
    "wed" => 3,
    "wednesday" => 3,
    "thu" => 4,
    "thursday" => 4,
    "fri" => 5,
    "friday" => 5,
    "sat" => 6,
    "saturday" => 6
  }

  @type cron :: %__MODULE__{
          minutes: MapSet.t(integer()),
          hours: MapSet.t(integer()),
          dom: MapSet.t(integer()),
          months: MapSet.t(integer()),
          dow: MapSet.t(integer()),
          dom_restricted: boolean(),
          dow_restricted: boolean()
        }

  @spec parse(String.t()) :: {:ok, cron()} | {:error, term()}
  def parse(expression) when is_binary(expression) do
    expression
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> case do
      [minute, hour, dom, month, dow] ->
        with {:ok, {minutes, _}} <- parse_field(minute, 0, 59, %{}),
             {:ok, {hours, _}} <- parse_field(hour, 0, 23, %{}),
             {:ok, {dom_set, dom_restricted}} <- parse_field(dom, 1, 31, %{}),
             {:ok, {months, _}} <- parse_field(month, 1, 12, @month_names),
             {:ok, {dow_set, dow_restricted}} <- parse_field(dow, 0, 7, @day_names) do
          dow_set =
            dow_set
            |> Enum.map(fn
              7 -> 0
              value -> value
            end)
            |> MapSet.new()

          if empty_field?(minutes) or empty_field?(hours) or empty_field?(dom_set) or
               empty_field?(months) or empty_field?(dow_set) do
            {:error, :empty_field}
          else
            {:ok,
             %__MODULE__{
               minutes: minutes,
               hours: hours,
               dom: dom_set,
               months: months,
               dow: dow_set,
               dom_restricted: dom_restricted,
               dow_restricted: dow_restricted
             }}
          end
        end

      _ ->
        {:error, :invalid_field_count}
    end
  end

  @spec next(String.t(), DateTime.t() | NaiveDateTime.t()) ::
          {:ok, DateTime.t() | NaiveDateTime.t()} | {:error, term()}
  def next(expression, %DateTime{} = datetime) when is_binary(expression) do
    with {:ok, cron} <- parse(expression) do
      naive = DateTime.to_naive(datetime)

      case next_naive(cron, naive) do
        {:ok, result_naive} ->
          conversion =
            if fixed_offset_zone?(datetime) do
              {:ok,
               %DateTime{
                 year: result_naive.year,
                 month: result_naive.month,
                 day: result_naive.day,
                 hour: result_naive.hour,
                 minute: result_naive.minute,
                 second: 0,
                 microsecond: {0, 0},
                 time_zone: datetime.time_zone,
                 utc_offset: datetime.utc_offset,
                 std_offset: datetime.std_offset,
                 calendar: result_naive.calendar
               }}
            else
              DateTime.from_naive(result_naive, datetime.time_zone)
            end

          case conversion do
            {:ok, result} -> {:ok, result}
            {:ambiguous, result, _other} -> {:ok, result}
            {:gap, result, _other} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end

        error ->
          error
      end
    end
  end

  def next(expression, %NaiveDateTime{} = datetime) when is_binary(expression) do
    with {:ok, cron} <- parse(expression) do
      next_naive(cron, datetime)
    end
  end

  @spec next_occurrences(String.t(), DateTime.t() | NaiveDateTime.t(), non_neg_integer()) ::
          {:ok, [DateTime.t() | NaiveDateTime.t()]} | {:error, term()}
  def next_occurrences(expression, datetime, count \\ 5)
      when is_binary(expression) and is_integer(count) and count >= 0 do
    with {:ok, _cron} <- parse(expression) do
      {:ok, collect_occurrences(expression, datetime, count, [])}
    end
  end

  @spec next_from_now(String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def next_from_now(expression) when is_binary(expression) do
    next(expression, DateTime.utc_now())
  end

  @spec matches?(String.t(), DateTime.t() | NaiveDateTime.t()) :: boolean()
  def matches?(expression, %DateTime{} = datetime) when is_binary(expression) do
    case parse(expression) do
      {:ok, cron} -> matches_naive?(cron, DateTime.to_naive(datetime))
      {:error, _reason} -> false
    end
  end

  def matches?(expression, %NaiveDateTime{} = datetime) when is_binary(expression) do
    case parse(expression) do
      {:ok, cron} -> matches_naive?(cron, datetime)
      {:error, _reason} -> false
    end
  end

  @doc "Returns whether the expression is a valid five-field cron expression."
  @spec valid?(String.t()) :: boolean()
  def valid?(expression) when is_binary(expression) do
    match?({:ok, _cron}, parse(expression))
  end

  defp collect_occurrences(_expression, _datetime, 0, acc) do
    Enum.reverse(acc)
  end

  defp collect_occurrences(expression, datetime, count, acc) do
    case next(expression, datetime) do
      {:ok, result} -> collect_occurrences(expression, result, count - 1, [result | acc])
      {:error, _reason} -> Enum.reverse(acc)
    end
  end

  defp next_naive(cron, datetime) do
    candidate =
      datetime
      |> zero_seconds()
      |> NaiveDateTime.add(60, :second)

    search(cron, candidate, 0)
  end

  defp search(_cron, _datetime, days) when days > 1826 do
    {:error, :no_occurrence_within_range}
  end

  defp search(cron, datetime, days) do
    date = NaiveDateTime.to_date(datetime)

    case find_on_date(cron, date, datetime.hour, datetime.minute) do
      {:ok, {hour, minute}} ->
        {:ok, NaiveDateTime.new!(date, Time.new!(hour, minute, 0))}

      :none ->
        next_date = Date.add(date, 1)
        next_datetime = NaiveDateTime.new!(next_date, ~T[00:00:00])
        search(cron, next_datetime, days + 1)
    end
  end

  defp find_on_date(cron, date, min_hour, min_minute) do
    cond do
      not MapSet.member?(cron.months, date.month) ->
        :none

      not day_allowed?(cron, date) ->
        :none

      true ->
        cron.hours
        |> Enum.sort()
        |> Enum.find_value(fn hour ->
          if hour < min_hour do
            nil
          else
            minutes = Enum.sort(cron.minutes)

            chosen =
              if hour == min_hour do
                Enum.find(minutes, &(&1 >= min_minute))
              else
                List.first(minutes)
              end

            if chosen, do: {hour, chosen}, else: nil
          end
        end)
        |> case do
          nil -> :none
          value -> {:ok, value}
        end
    end
  end

  defp day_allowed?(cron, date) do
    dom_allowed = MapSet.member?(cron.dom, date.day)
    dow_allowed = MapSet.member?(cron.dow, day_of_week_cron(date))

    cond do
      cron.dom_restricted and cron.dow_restricted -> dom_allowed or dow_allowed
      cron.dom_restricted -> dom_allowed
      cron.dow_restricted -> dow_allowed
      true -> true
    end
  end

  defp day_of_week_cron(date) do
    case Date.day_of_week(date) do
      7 -> 0
      value -> value
    end
  end

  defp matches_naive?(cron, datetime) do
    date = NaiveDateTime.to_date(datetime)

    MapSet.member?(cron.minutes, datetime.minute) and
      MapSet.member?(cron.hours, datetime.hour) and
      MapSet.member?(cron.months, date.month) and
      day_allowed?(cron, date)
  end

  defp zero_seconds(%NaiveDateTime{} = datetime) do
    %{datetime | second: 0, microsecond: {0, 0}}
  end

  defp empty_field?(set), do: MapSet.size(set) == 0

  defp parse_field(field, min, max, names) when is_binary(field) do
    restricted = field not in ["*", "?"]
    parts = String.split(field, ",")

    Enum.reduce_while(parts, {:ok, MapSet.new()}, fn part, {:ok, acc} ->
      case parse_part(part, min, max, names) do
        {:ok, values} -> {:cont, {:ok, MapSet.union(acc, values)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, set} ->
        if MapSet.size(set) == 0 do
          {:error, :empty_field}
        else
          {:ok, {set, restricted}}
        end

      error ->
        error
    end
  end

  defp parse_part(part, min, max, names) do
    with {:ok, {base, step}} <- split_step(part),
         {:ok, {low, high}} <- parse_range(base, min, max, names) do
      values =
        for value <- low..high, rem(value - low, step) == 0 do
          if max == 7 and value == 7 do
            0
          else
            value
          end
        end

      {:ok, MapSet.new(values)}
    else
      _ -> {:error, :invalid_field}
    end
  end

  defp split_step(part) do
    case String.split(String.trim(part), "/", parts: 2) do
      [base] ->
        {:ok, {String.trim(base), 1}}

      [base, step_string] ->
        case Integer.parse(String.trim(step_string)) do
          {step, ""} when step > 0 -> {:ok, {String.trim(base), step}}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_range(base, min, max, names) do
    cond do
      base in ["*", "?"] ->
        {:ok, {min, max}}

      String.contains?(base, "-") ->
        case String.split(base, "-", parts: 2) do
          [left, right] ->
            with {:ok, low} <- parse_value(String.trim(left), min, max, names),
                 {:ok, high} <- parse_value(String.trim(right), min, max, names) do
              if low <= high do
                {:ok, {low, high}}
              else
                :error
              end
            end

          _ ->
            :error
        end

      true ->
        case parse_value(base, min, max, names) do
          {:ok, value} -> {:ok, {value, value}}
          :error -> :error
        end
    end
  end

  defp parse_value(token, min, max, names) do
    token = String.trim(token)
    downcased = String.downcase(token)

    case Map.get(names, downcased) do
      nil ->
        case Integer.parse(token) do
          {value, ""} when value >= min and value <= max -> {:ok, value}
          _ -> :error
        end

      value when value >= min and value <= max ->
        {:ok, value}

      _ ->
        :error
    end
  end

  defp fixed_offset_zone?(%DateTime{} = datetime) do
    (datetime.time_zone == "Etc/UTC" and datetime.utc_offset != 0) or
      (is_binary(datetime.time_zone) and
         Regex.match?(~r/^[+-]\d{2}:\d{2}$/, datetime.time_zone))
  end
end
