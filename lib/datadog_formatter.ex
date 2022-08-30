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
      format_metadata(sanitized_metadata, raw_metadata)
    )
  end

  defp format_metadata(metadata, raw_metadata) do
    metadata
    |> skip_metadata_keys()
    |> maybe_put(:error, format_process_crash(raw_metadata))
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

  defp format_initial_call(nil), do: nil
  defp format_initial_call({module, function, arity}), do: format_function(module, function, arity)

  defp format_function(nil, function), do: function
  defp format_function(module, function), do: "#{inspect(module)}.#{function}"
  defp format_function(module, function, arity), do: "#{inspect(module)}.#{function}/#{arity}"

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def format_process_crash(metadata) do
    if crash_reason = Map.get(metadata, :crash_reason) do
      initial_call = Map.get(metadata, :initial_call)

      json_map(
        initial_call: format_initial_call(initial_call),
        reason: format_crash_reason(crash_reason)
      )
    end
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

  defp format_crash_reason({:throw, reason}) do
    Exception.format(:throw, reason)
  end

  defp format_crash_reason({:exit, reason}) do
    Exception.format(:exit, reason)
  end

  defp format_crash_reason({%{} = exception, stacktrace}) do
    Exception.format(:error, exception, stacktrace)
  end

  defp format_crash_reason(other) do
    inspect(other)
  end
end
