defmodule StathamLogger.ExceptionCapturePlug do
  @moduledoc """
  Send Endpoint error manually to stdout, instead of relying on default error logged.

  This workaround was necessary because default error
  doesn't have the custom Logger metadata that StathamLogger needs (`logger_context` etc.)

  To avoid duplicate logs in Datadog, the default error is ignored in StathamLogger
  (can be un-ignored by setting `exception_capture_plug_used?` to false).

  #### Usage
  In a Phoenix application, it is important to use this module before
  the Phoenix endpoint itself. It should be added to your endpoint.ex:
      defmodule MyApp.Endpoint
        use StathamLogger.ExceptionCapturePlug
        use Phoenix.Endpoint, otp_app: :my_app
        # ...
      end
  """

  require Logger

  alias StathamLogger.Sanitizer
  alias StathamLogger.DatadogFormatter

  defmacro __using__(_opts) do
    quote do
      @before_compile StathamLogger.ExceptionCapturePlug
    end
  end

  defmacro __before_compile__(_) do
    quote do
      defoverridable call: 2

      def call(conn, opts) do
        try do
          super(conn, opts)
        rescue
          e in Plug.Conn.WrapperError ->
            write_exception_to_stdout(conn, e.reason, e.stack)
            Plug.Conn.WrapperError.reraise(conn, e.kind, e.reason, e.stack)

          e ->
            write_exception_to_stdout(conn, e.reason, __STACKTRACE__)
            :erlang.raise(:error, e, __STACKTRACE__)
        catch
          kind, reason ->
            write_exception_to_stdout(conn, reason, __STACKTRACE__)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end
      end

      defp write_exception_to_stdout(conn, reason, stacktrace) do
        raw_metadata =
          Logger.metadata()
          |> Keyword.merge(
            crash_reason: {
              reason,
              stacktrace
            }
          )
          |> Map.new()

        message = exception_message(conn, self(), __MODULE__, reason, stacktrace)

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

      # Code copied from `plug_cowboy` Plug.Cowboy.Translator START
      defp exception_message(conn, pid, mod, reason, stacktrace) do
        [
          inspect(pid),
          " running ",
          inspect(mod),
          " terminated\n",
          conn_info(conn)
          | Exception.format(:exit, {reason, stacktrace}, [])
        ]
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
  end
end
