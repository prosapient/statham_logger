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

  alias StathamLogger.ExceptionLogger

  defmacro __using__(_opts) do
    quote do
      @before_compile StathamLogger.ExceptionCapturePlug
    end
  end

  defmacro __before_compile__(_) do
    quote do
      defoverridable call: 2

      def call(conn, opts) do
        super(conn, opts)
      rescue
        e in Plug.Conn.WrapperError ->
          if Plug.Exception.status(e.reason) >= 500 do
            ExceptionLogger.write_exception_to_stdout(e.reason, e.stack, conn)
          end

          Plug.Conn.WrapperError.reraise(conn, e.kind, e.reason, e.stack)

        e ->
          if Plug.Exception.status(e) >= 500 do
            ExceptionLogger.write_exception_to_stdout(e, __STACKTRACE__, conn)
          end

          :erlang.raise(:error, e, __STACKTRACE__)
      catch
        kind, reason ->
          if Plug.Exception.status(reason) >= 500 do
            ExceptionLogger.write_exception_to_stdout(reason, __STACKTRACE__, conn)
          end

          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end
end
