defmodule StathamLogger.DatadogFormatter do
  @moduledoc """
  Datadog-specific formatting

  Adheres to the
  [default standard attribute list](https://docs.datadoghq.com/logs/processing/attributes_naming_convention/#default-standard-attribute-list).

  Some code is borrowed from Nebo15 [logger_json](https://github.com/Nebo15/logger_json/blob/master/lib/logger_json/formatters/datadog_logger.ex):
  """
  import Jason.Helpers, only: [json_map: 1]

  @skipped_metadata_keys [:domain, :erl_level, :gl, :time]

  def format_event(level, message, timestamp, raw_metadata, sanitized_metadata) do
    Map.merge(
      %{
        logger:
          json_map(
            thread_name: inspect(Map.get(raw_metadata, :pid)),
            method_name: method_name(raw_metadata)
          ),
        message: IO.chardata_to_string(message),
        syslog:
          json_map(
            hostname: node_hostname(),
            severity: Atom.to_string(level),
            timestamp: format_timestamp(timestamp)
          )
      },
      skip_metadata_keys(sanitized_metadata)
    )
    |> maybe_put(:error, format_error(raw_metadata))
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
  defp format_function(module, function, arity), do: "#{inspect(module)}.#{function}/#{arity}"

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_error(%{crash_reason: {error, stacktrace}} = metadata) when is_list(stacktrace) do
    Map.merge(
      format_crash_reason_error(error),
      %{
        stack: format_crash_reason_stacktrace(stacktrace)
      }
    )
  end

  defp format_error(_metadata), do: nil

  defp format_crash_reason_error(%{__exception__: true, __struct__: struct} = exception) do
    %{
      kind: inspect(struct),
      message: Exception.format_banner(:error, exception)
    }
  end

  defp format_crash_reason_error({:no_catch, reason}) do
    %{
      kind: :throw,
      message: Exception.format_banner(:throw, reason, [])
    }
  end

  defp format_crash_reason_error(error) do
    %{
      kind: :exit,
      message: Exception.format_banner(:exit, error)
    }
  end

  defp format_crash_reason_stacktrace(stacktrace) do
    Exception.format_stacktrace(stacktrace)
  end

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
