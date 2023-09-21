defmodule StathamLogger.ExceptionLogger do
  require Logger

  alias StathamLogger.Sanitizer
  alias StathamLogger.DatadogFormatter

  def write_exception_to_stdout(error, stacktrace, conn \\ nil) do
    if statham_logger_running?() do
      raw_metadata =
        Logger.metadata()
        |> Keyword.merge(
          crash_reason: {
            error,
            stacktrace
          }
        )
        |> Map.new()

      message = exception_message(self(), __MODULE__, error, stacktrace, conn)

      {_, _, microseconds} = system_time = :erlang.timestamp()
      {date, {hh, mm, ss}} = :calendar.now_to_local_time(system_time)

      timestamp = {
        date,
        {hh, mm, ss, div(microseconds, 1_000)}
      }

      sanitized_metadata =
        raw_metadata
        |> Sanitizer.sanitize_metadata()

      message
      |> DatadogFormatter.format_captured_exception(timestamp, sanitized_metadata, raw_metadata)
      |> Jason.encode_to_iodata!()
      |> IO.puts()
    end
  end

  defp statham_logger_running? do
    supervisor =
      if Process.whereis(Logger.BackendSupervisor) do
        Logger.BackendSupervisor
      else
        Logger.Backends.Supervisor
      end

    supervisor
    |> Supervisor.which_children()
    |> Enum.any?(fn spec -> elem(spec, 0) == StathamLogger end)
  end

  # Code copied from `plug_cowboy` Plug.Cowboy.Translator START
  defp exception_message(pid, mod, reason, stacktrace, conn) do
    [
      inspect(pid),
      " running ",
      inspect(mod),
      " terminated\n",
      conn_info(conn)
      | Exception.format(:exit, {reason, stacktrace}, [])
    ]
  end

  defp conn_info(nil) do
    []
  end

  defp conn_info(conn) do
    [server_info(conn), request_info(conn)]
  end

  defp server_info(%Plug.Conn{host: host, port: :undefined, scheme: scheme}) do
    ["Server: ", host, ?\s, ?(, Atom.to_string(scheme), ?), ?\n]
  end

  defp server_info(%Plug.Conn{host: host, port: port, scheme: scheme}) do
    ["Server: ", host, ":", Integer.to_string(port), ?\s, ?(, Atom.to_string(scheme), ?), ?\n]
  end

  defp request_info(%Plug.Conn{method: method, query_string: query_string} = conn) do
    ["Request: ", method, ?\s, path_to_iodata(conn.request_path, query_string), ?\n]
  end

  defp path_to_iodata(path, ""), do: path
  defp path_to_iodata(path, qs), do: [path, ??, qs]
  # Code copied from `plug_cowboy` Plug.Cowboy.Translator END
end
