defmodule StathamLogger.ExceptionCapturePlugTest do
  use ExUnit.Case
  use Plug.Test

  import ExUnit.CaptureIO

  defmodule PhoenixController do
    use Phoenix.Controller
    def error(_conn, _params), do: raise("PhoenixError")
    def exit(_conn, _params), do: exit(:test)
    def throw(_conn, _params), do: throw(:test)
  end

  defmodule PhoenixRouter do
    use Phoenix.Router

    get("/error_route", PhoenixController, :error)
    get("/exit_route", PhoenixController, :exit)
    get("/throw_route", PhoenixController, :throw)
    get("/assigns_route", PhoenixController, :assigns)
  end

  defmodule PhoenixEndpoint do
    use StathamLogger.ExceptionCapturePlug
    use Phoenix.Endpoint, otp_app: :statham_logger_test_phoenix_app
    use Plug.Debugger, otp_app: :statham_logger_test_phoenix_app

    plug(PhoenixRouter)
  end

  test "report errors occurring in Phoenix Endpoint" do
    PhoenixEndpoint.start_link()

    assert capture_io(fn ->
             assert_raise RuntimeError, "PhoenixError", fn ->
               conn(:get, "/error_route")
               |> PhoenixEndpoint.call([])
             end
           end) =~ "error\":{\"kind\":\"RuntimeError\""
  end

  test "report exits occurring in Phoenix Endpoint" do
    PhoenixEndpoint.start_link()

    assert capture_io(fn ->
             catch_exit(
               conn(:get, "/exit_route")
               |> PhoenixEndpoint.call([])
             )
           end) =~ "error\":{\"kind\":\"exit\""
  end

  test "report throws occurring in Phoenix Endpoint" do
    PhoenixEndpoint.start_link()

    assert capture_io(fn ->
             catch_throw(conn(:get, "/throw_route") |> PhoenixEndpoint.call([]))
           end) =~ "error\":{\"kind\":\"exit\""
  end

  test "don't report Plug exceptions with status < 500" do
    PhoenixEndpoint.start_link()

    assert capture_io(fn ->
             assert_raise Phoenix.Router.NoRouteError, fn ->
               conn(:get, "/bad_route")
               |> PhoenixEndpoint.call([])
             end
           end) == ""
  end

  test "reported errors are JSON-encoded" do
    PhoenixEndpoint.start_link()

    result =
      capture_io(fn ->
        assert_raise RuntimeError, "PhoenixError", fn ->
          conn(:get, "/error_route")
          |> PhoenixEndpoint.call([])
        end
      end)

    decoded_result = Jason.decode!(result)

    assert %{
             "crash_reason" => [%{"__exception__" => true, "message" => "PhoenixError"}, [_ | _stacktrace]],
             "error" => %{
               "kind" => "RuntimeError",
               "message" => "** (RuntimeError) PhoenixError",
               "stack" => _
             },
             "message" => message,
             "syslog" => %{
               "hostname" => _,
               "severity" => "error",
               "timestamp" => _
             }
           } = decoded_result

    assert message =~
             "Request: GET /error_route\n** (exit) an exception was raised:\n    ** (RuntimeError) PhoenixError\n"
  end
end
