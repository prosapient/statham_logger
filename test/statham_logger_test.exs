defmodule StathamLoggerTest do
  use StathamLogger.LoggerCase, async: false
  import ExUnit.CaptureIO
  require Logger

  defmodule IDStruct, do: defstruct(id: nil)

  setup do
    Logger.remove_backend(:console)
    Logger.add_backend(StathamLogger)

    :ok =
      Logger.configure_backend(
        StathamLogger,
        device: :user,
        level: nil,
        metadata: []
      )

    :ok = Logger.reset_metadata([])
  end

  describe "@derive StathamLogger.Loggable" do
    test "allows Structs to override sanitize options" do
      Logger.configure_backend(StathamLogger,
        metadata: :all,
        sanitize_options: [
          filter_keys: {:discard, [:password]},
          max_string_size: 4
        ]
      )

      Logger.metadata(
        user: %StathamLogger.LoggableStructWithDiscard{
          name: "Long Name",
          password: "123",
          phone_number: "123"
        }
      )

      log =
        fn -> Logger.debug("") end
        |> capture_log()
        |> Jason.decode!()

      assert %{
               "user" => %{
                 "name" => "Long...",
                 "password" => "123",
                 "phone_number" => "[FILTERED]"
               }
             } = log

      Logger.metadata(
        user: %StathamLogger.LoggableStructWithKeep{
          name: "Long Name",
          password: "123",
          phone_number: "123"
        }
      )

      log =
        fn -> Logger.debug("") end
        |> capture_log()
        |> Jason.decode!()

      assert %{
               "user" => %{
                 "name" => "Long...",
                 "password" => "[FILTERED]",
                 "phone_number" => "123"
               }
             } = log
    end
  end

  test "logs empty binary messages" do
    Logger.configure_backend(StathamLogger, metadata: :all)

    log =
      fn -> Logger.debug("") end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => ""} = log
  end

  test "logs binary messages" do
    Logger.configure_backend(StathamLogger, metadata: :all)

    log =
      fn -> Logger.debug("hello") end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => "hello"} = log
  end

  test "logs empty iodata messages" do
    Logger.configure_backend(StathamLogger, metadata: :all)

    log =
      fn -> Logger.debug([]) end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => ""} = log
  end

  test "logs iodata messages" do
    Logger.configure_backend(StathamLogger, metadata: :all)

    log =
      fn -> Logger.debug([?h, ?e, ?l, ?l, ?o]) end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => "hello"} = log
  end

  test "logs chardata messages" do
    Logger.configure_backend(StathamLogger, metadata: :all)

    log =
      fn -> Logger.debug([?π, ?α, ?β]) end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => "παβ"} = log
  end

  test "log message does not break escaping" do
    Logger.configure_backend(StathamLogger, metadata: :all)

    log =
      fn -> Logger.debug([?", ?h]) end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => "\"h"} = log

    log =
      fn -> Logger.debug("\"h") end
      |> capture_log()
      |> Jason.decode!()

    assert %{"message" => "\"h"} = log
  end

  test "does not start when there is no user" do
    :ok = Logger.remove_backend(StathamLogger)
    user = Process.whereis(:user)

    try do
      Process.unregister(:user)
      assert {:error, :ignore} == :gen_event.add_handler(Logger, StathamLogger, StathamLogger)
    after
      Process.register(user, :user)
    end
  after
    {:ok, _} = Logger.add_backend(StathamLogger)
  end

  test "may use another device" do
    Logger.configure_backend(StathamLogger, device: :standard_error)

    assert capture_io(:standard_error, fn ->
             Logger.debug("hello")
             Logger.flush()
           end) =~ "hello"
  end

  describe "metadata" do
    test "can be configured" do
      Logger.configure_backend(StathamLogger, metadata: [:user_id])

      assert capture_log(fn ->
               Logger.debug("hello")
             end) =~ "hello"

      Logger.metadata(user_id: 13)

      log =
        fn -> Logger.debug("hello") end
        |> capture_log()
        |> Jason.decode!()

      assert %{"user_id" => 13} = log
    end

    test "can be configured to :all" do
      Logger.configure_backend(StathamLogger, metadata: :all)

      Logger.metadata(user_id: 11)
      Logger.metadata(dynamic_metadata: 5)

      log =
        fn -> Logger.debug("hello") end
        |> capture_log()
        |> Jason.decode!()

      assert %{"user_id" => 11} = log
      assert %{"dynamic_metadata" => 5} = log
    end

    test "can be empty" do
      Logger.configure_backend(StathamLogger, metadata: [])

      log =
        fn -> Logger.debug("hello") end
        |> capture_log()
        |> Jason.decode!()

      assert %{"message" => "hello"} = log
    end

    test "skip some otp metadata fields" do
      Logger.configure_backend(StathamLogger, metadata: :all)

      debug_fn = fn -> Logger.debug("hello") end

      log =
        debug_fn
        |> capture_log()
        |> Jason.decode!()

      refute log["time"]
      refute log["domain"]
      refute log["erl_level"]
      refute log["gl"]

      assert log["file"]
      assert log["function"]
      assert log["mfa"]
      assert log["module"]
      assert log["pid"]
    end

    test "converts Struct metadata to maps" do
      Logger.configure_backend(StathamLogger, metadata: :all)

      Logger.metadata(id_struct: %IDStruct{id: "test"})

      debug_fn = fn -> Logger.debug("hello") end

      log =
        debug_fn
        |> capture_log()
        |> Jason.decode!()

      assert %{"id_struct" => %{"id" => "test"}} = log
    end
  end

  test "contains source location" do
    %{module: mod, function: {name, arity}, file: _file, line: _line} = __ENV__

    log =
      fn -> Logger.debug("hello") end
      |> capture_log()
      |> Jason.decode!()

    function = "#{inspect(mod)}.#{name}/#{arity}"

    assert %{
             "logger" => %{
               "method_name" => ^function
             }
           } = log
  end

  test "may configure level" do
    Logger.configure_backend(StathamLogger, level: :info)

    assert capture_log(fn ->
             Logger.debug("hello")
           end) == ""
  end

  test "logs severity" do
    log =
      fn -> Logger.debug("hello") end
      |> capture_log()
      |> Jason.decode!()

    assert %{"syslog" => %{"severity" => "debug"}} = log

    log =
      fn -> Logger.warn("hello") end
      |> capture_log()
      |> Jason.decode!()

    assert %{"syslog" => %{"severity" => "warn"}} = log
  end

  test "logs crash reason when present" do
    Logger.configure_backend(StathamLogger, metadata: [:crash_reason])
    Logger.metadata(crash_reason: {%RuntimeError{message: "oops"}, []})

    log =
      capture_log(fn -> Logger.debug("hello") end)
      |> Jason.decode!()

    assert %{
             "kind" => "RuntimeError",
             "message" => "** (RuntimeError) oops",
             "stack" => [],
             "initial_call" => nil
           } = log["error"]
  end

  @tag :wip
  test "logs erlang style crash reasons" do
    Logger.configure_backend(StathamLogger, metadata: [:crash_reason])
    Logger.metadata(crash_reason: {:socket_closed_unexpectedly, []})

    log =
      capture_log(fn -> Logger.debug("hello") end)
      |> Jason.decode!()

    assert %{
             "kind" => "exit",
             "message" => "** (exit) :socket_closed_unexpectedly",
             "stack" => [],
             "initial_call" => nil
           } = log["error"]
  end

  test "logs initial call when present" do
    Logger.configure_backend(StathamLogger, metadata: [:initial_call])
    Logger.metadata(crash_reason: {%RuntimeError{message: "oops"}, []}, initial_call: {Foo, :bar, 3})

    log =
      capture_log(fn -> Logger.debug("hello") end)
      |> Jason.decode!()

    assert log["error"]["initial_call"] == "Foo.bar/3"
  end

  test "hides sensitive data" do
    Logger.configure_backend(StathamLogger,
      metadata: :all,
      sanitize_options: [filter_keys: {:discard, [:password]}]
    )

    Logger.metadata(
      request: %{
        password: "secret",
        name: "not a secret"
      }
    )

    log =
      fn -> Logger.debug("hello") end
      |> capture_log()
      |> Jason.decode!()

    assert %{
             "request" => %{
               "name" => "not a secret",
               "password" => "[FILTERED]"
             }
           } = log
  end
end
