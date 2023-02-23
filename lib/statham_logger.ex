defmodule StathamLogger do
  @moduledoc ~S"""
  Elixir Logger backend with Datadog integration and extensible formatting.

  Code is mostly borrowed from built-in Elixir [:console Logger backend](https://github.com/elixir-lang/elixir/blob/master/lib/logger/lib/logger/backends/console.ex)

  ## Options

    * `:level` - the level to be logged by this backend.
      Note that messages are filtered by the general
      `:level` configuration for the `:logger` application first.

    * `:metadata` - the metadata to be printed by `$metadata`.
      Defaults to an empty list (no metadata).
      Setting `:metadata` to `:all` prints all metadata. See
      the "Metadata" section for more information.

    * `:sanitize_options` - options, passed as a second argument to
    `StathamLogger.Loggable.sanitize/2` implementations.
    Built-in implementations use `:filter_keys` and `:max_string_size` options:

      * `:filter_keys` - specify confidential keys, to hide corresponding values from metadata.
      Defaults to `[]`\
      For example, given metadata:
      ```elixir
      [
          request: %{user_id: "id"}
      ]
      ```
      and `filter_keys: {:discard, [:user_id]}`
      resulting JSON would be
      ```json
      {
          "request": {"user_id" => "[FILTERED]"}
      }
      ```

      * `:max_string_size` - maximum length of string values. Defaults to `nil`.\
      For example, given `max_string_size: 10` => "Lorem ipsu...".

    * `:device` - the device to log error messages to. Defaults to
      `:user` but can be changed to something else such as `:standard_error`.

    * `:max_buffer` - maximum events to buffer while waiting
      for a confirmation from the IO device (default: 32).
      Once the buffer is full, the backend will block until
      a confirmation is received.

    * `exception_capture_plug_used?` - if true, StathamLogger ignores the logged Endpoint error,
      received by StathamLogger backend, relying instead on error logged by StathamLogger.ExceptionCapturePlug.
      `true` by default. Has to be true to avoid duplicate errors sent to Datadog.

  ## Implementing sanitization for new types can be done in 3 ways:
    1. Implement `StathamLogger.Loggable` protocol. Most flexible approach.
    ```elixir
    defmodule YourStruct do
      ...
    end
    defimpl StathamLogger.Loggable, for: YourStruct do
      @impl true
      def sanitize(struct, opts) do
          # your sanitization logic
      end
    end
    ```

    2. Derive StathamLogger.Loggable, optionally override options.
    ```elixir
    defmodule YourStruct do
      @derive {StathamLogger.Loggable, filter_keys: {:discard, [:phone_number]}}
      struct [:phone_number, ...]
    end
    ```

    3. Derive Jason.Encoder (not recommended)
    ```elixir
    defmodule YourStruct do
      @derive {Jason.Encoder, only: [:foo]}
      ...
    end
    ```
  """

  alias StathamLogger.DatadogFormatter
  alias StathamLogger.Sanitizer

  @behaviour :gen_event

  defstruct buffer: [],
            buffer_size: 0,
            device: nil,
            level: nil,
            max_buffer: nil,
            metadata: :all,
            sanitize_options: [],
            output: nil,
            ref: nil,
            exception_capture_plug_used?: true

  @impl true
  def init(__MODULE__) do
    config = config()
    device = Keyword.get(config, :device, :user)

    if Process.whereis(device) do
      {:ok, init(config, %__MODULE__{})}
    else
      {:error, :ignore}
    end
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    config = configure_merge(config(), opts)
    {:ok, init(config, %__MODULE__{})}
  end

  @impl true
  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  @impl true
  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    %{level: log_level, ref: ref, buffer_size: buffer_size, max_buffer: max_buffer} = state

    cond do
      not meet_level?(level, log_level) ->
        {:ok, state}

      filtered_by_exception_capture_plug?(md, state) ->
        {:ok, state}

      is_nil(ref) ->
        {:ok, log_event(level, msg, ts, md, state)}

      buffer_size < max_buffer ->
        {:ok, buffer_event(level, msg, ts, md, state)}

      buffer_size === max_buffer ->
        state = buffer_event(level, msg, ts, md, state)
        {:ok, await_io(state)}
    end
  end

  def handle_event(:flush, state) do
    {:ok, flush(state)}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:io_reply, ref, msg}, %{ref: ref} = state) do
    {:ok, handle_io_reply(msg, state)}
  end

  def handle_info({:DOWN, ref, _, pid, reason}, %{ref: ref}) do
    raise "device #{inspect(pid)} exited: " <> Exception.format_exit(reason)
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @impl true
  @spec terminate(any, any) :: :ok
  def terminate(_reason, _state) do
    :ok
  end

  ## Helpers

  defp meet_level?(_lvl, nil), do: true

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp filtered_by_exception_capture_plug?(md, %{exception_capture_plug_used?: exception_capture_plug_used?}) do
    exception_capture_plug_used? &&
      Keyword.has_key?(md, :conn) &&
      Keyword.has_key?(md, :crash_reason)
  end

  defp configure(options, state) do
    config = configure_merge(config(), options)
    Application.put_env(:logger, StathamLogger, config)
    init(config, state)
  end

  defp init(config, state) do
    level = Keyword.get(config, :level, :debug)
    device = Keyword.get(config, :device, :user)
    max_buffer = Keyword.get(config, :max_buffer, 32)
    sanitize_options = Keyword.get(config, :sanitize_options, [])
    exception_capture_plug_used? = Keyword.get(config, :exception_capture_plug_used?, true)

    metadata =
      config
      |> Keyword.get(:metadata, :all)
      |> configure_metadata()

    %{
      state
      | metadata: metadata,
        level: level,
        device: device,
        max_buffer: max_buffer,
        sanitize_options: sanitize_options,
        exception_capture_plug_used?: exception_capture_plug_used?
    }
  end

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp configure_merge(env, options), do: Keyword.merge(env, options, fn _key, _v1, v2 -> v2 end)

  defp log_event(level, msg, ts, md, %{device: device} = state) do
    output = format_event(level, msg, ts, md, state)
    %{state | ref: async_io(device, output), output: output}
  end

  defp buffer_event(level, msg, ts, md, state) do
    %{buffer: buffer, buffer_size: buffer_size} = state
    buffer = [buffer | format_event(level, msg, ts, md, state)]
    %{state | buffer: buffer, buffer_size: buffer_size + 1}
  end

  defp async_io(name, output) when is_atom(name) do
    case Process.whereis(name) do
      device when is_pid(device) ->
        async_io(device, output)

      nil ->
        raise "no device registered with the name #{inspect(name)}"
    end
  end

  defp async_io(device, output) when is_pid(device) do
    ref = Process.monitor(device)
    send(device, {:io_request, self(), ref, {:put_chars, :unicode, output}})
    ref
  end

  defp await_io(%{ref: nil} = state), do: state

  defp await_io(%{ref: ref} = state) do
    receive do
      {:io_reply, ^ref, :ok} ->
        handle_io_reply(:ok, state)

      {:io_reply, ^ref, error} ->
        error
        |> handle_io_reply(state)
        |> await_io()

      {:DOWN, ^ref, _, pid, reason} ->
        raise "device #{inspect(pid)} exited: " <> Exception.format_exit(reason)
    end
  end

  defp format_event(
         level,
         message,
         timestamp,
         metadata,
         %{metadata: filter_keys, sanitize_options: sanitize_options} = _state
       ) do
    raw_metadata = Map.new(metadata)
    sanitized_metadata = Sanitizer.sanitize_metadata(raw_metadata, filter_keys, sanitize_options)
    event = DatadogFormatter.format_event(level, message, timestamp, sanitized_metadata, raw_metadata)

    [Jason.encode_to_iodata!(event) | "\n"]
  end

  defp log_buffer(%{buffer_size: 0, buffer: []} = state), do: state

  defp log_buffer(state) do
    %{device: device, buffer: buffer} = state
    %{state | ref: async_io(device, buffer), buffer: [], buffer_size: 0, output: buffer}
  end

  defp handle_io_reply(:ok, %{ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    log_buffer(%{state | ref: nil, output: nil})
  end

  defp handle_io_reply({:error, {:put_chars, :unicode, _} = error}, state) do
    retry_log(error, state)
  end

  defp handle_io_reply({:error, :put_chars}, %{output: output} = state) do
    retry_log({:put_chars, :unicode, output}, state)
  end

  defp handle_io_reply({:error, error}, _) do
    raise "failure while logging console messages: " <> inspect(error)
  end

  defp retry_log(error, %{device: device, ref: ref, output: dirty} = state) do
    Process.demonitor(ref, [:flush])

    try do
      :unicode.characters_to_binary(dirty)
    rescue
      ArgumentError ->
        clean = ["failure while trying to log malformed data: ", inspect(dirty), ?\n]
        %{state | ref: async_io(device, clean), output: clean}
    else
      {_, good, bad} ->
        clean = [good | Logger.Formatter.prune(bad)]
        %{state | ref: async_io(device, clean), output: clean}

      _ ->
        # A well behaved IO device should not error on good data
        raise "failure while logging consoles messages: " <> inspect(error)
    end
  end

  defp flush(%{ref: nil} = state), do: state

  defp flush(state) do
    state
    |> await_io()
    |> flush()
  end

  defp config do
    Application.get_env(:logger, StathamLogger, [])
  end
end
