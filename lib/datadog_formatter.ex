defmodule StathamLogger.DatadogFormatter do
  @moduledoc """
  Datadog-specific formatting

  Adheres to the
  [default standard attribute list](https://docs.datadoghq.com/logs/processing/attributes_naming_convention/#default-standard-attribute-list).
  """

  @skipped_metadata_keys [:domain, :erl_level, :gl, :time]

  @standard_attributes_list %{
    http: ~w(url status_code method referer request_id useragent)a,
    usr: ~w(id name email)a
  }

  def format_event(level, message, timestamp, sanitized_metadata, raw_metadata) do
    Map.merge(
      %{
        logger: %{
          thread_name: inspect(Map.get(raw_metadata, :pid)),
          method_name: method_name(raw_metadata)
        },
        message: IO.chardata_to_string(message),
        syslog: %{
          hostname: node_hostname(),
          severity: Atom.to_string(level),
          timestamp: format_timestamp(timestamp)
        }
      },
      skip_metadata_keys(sanitized_metadata)
    )
    |> maybe_put(:error, format_error(raw_metadata))
    |> maybe_put(:usr, format_user(raw_metadata))
    |> maybe_put(:http, format_http(raw_metadata))
  end

  def format_captured_exception(message, timestamp, sanitized_metadata, raw_metadata) do
    Map.merge(
      %{
        message: IO.chardata_to_string(message),
        syslog: %{
          hostname: node_hostname(),
          severity: "error",
          timestamp: format_timestamp(timestamp)
        }
      },
      skip_metadata_keys(sanitized_metadata)
    )
    |> maybe_put(:error, format_error(raw_metadata))
    |> maybe_put(:usr, format_user(raw_metadata))
    |> maybe_put(:http, format_http(raw_metadata))
  end

  defp skip_metadata_keys(metadata) do
    metadata
    |> Map.drop(@skipped_metadata_keys)
  end

  defp method_name(metadata) do
    function = Map.get(metadata, :function)
    module = Map.get(metadata, :module)

    format_function(module, function)
  end

  defp node_hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp format_function(nil, function), do: function
  defp format_function(module, function), do: "#{inspect(module)}.#{function}"

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_error(%{crash_reason: {error, stacktrace}}) when is_list(stacktrace) do
    Map.merge(
      format_crash_reason_error(error),
      %{
        stack: format_crash_reason_stacktrace(stacktrace)
      }
    )
  end

  defp format_error(_metadata), do: nil

  defp format_crash_reason_error(error) do
    cond do
      Kernel.is_exception(error) ->
        %{
          kind: Exception.format(:error, error),
          message: Exception.message(error)
        }

      match?({:no_catch, _}, error) ->
        {:no_catch, reason} = error

        %{
          kind: inspect(reason),
          message: Exception.format(:throw, reason)
        }

      true ->
        %{
          kind: inspect(error),
          message: Exception.format(:exit, error)
        }
    end
  end

  defp format_crash_reason_stacktrace(stacktrace) do
    Exception.format_stacktrace(stacktrace)
  end

  defp format_user(%{logger_context: %{user: user}}) when is_map(user) do
    Map.take(user, @standard_attributes_list.usr)
  end

  defp format_user(_), do: nil

  defp format_http(%{logger_context: %{http: http}}) when is_map(http) do
    Map.take(http, @standard_attributes_list.http)
  end

  defp format_http(_), do: nil

  defp format_timestamp({date, time}) do
    [format_date(date), ?T, format_time(time), ?Z]
    |> IO.iodata_to_binary()
  end

  defp format_time({hh, mi, ss, ms}) do
    [pad2(hh), ?:, pad2(mi), ?:, pad2(ss), ?., pad3(ms)]
  end

  defp format_date({yy, mm, dd}) do
    [Integer.to_string(yy), ?-, pad2(mm), ?-, pad2(dd)]
  end

  defp pad2(int) when int < 10, do: [?0, Integer.to_string(int)]
  defp pad2(int), do: Integer.to_string(int)

  defp pad3(int) when int < 10, do: [?0, ?0, Integer.to_string(int)]
  defp pad3(int) when int < 100, do: [?0, Integer.to_string(int)]
  defp pad3(int), do: Integer.to_string(int)
end
