# StathamLogger

Elixir app > Logger > **StathamLogger Logger Backend** > :stdout > Datadog Agent > Datadog

A backend for the Elixir [Logger](https://hexdocs.pm/logger/Logger.html) that:
- transforms logged [metadata](https://hexdocs.pm/logger/1.12/Logger.html#module-metadata), by hiding sensitive values and trimming long strings
- outputs JSON string, structured according to [Datadog attributest list](https://docs.datadoghq.com/logs/processing/attributes_naming_convention/#default-standard-attribute-list)

## Installation

```elixir
def deps do
  [
    {:statham_logger, github: "prosapient/statham_logger"}
  ]
end
```

## Configuration

1. Use `StathamLogger` Logger backend, instead of default [Console](https://github.com/elixir-lang/elixir/blob/master/lib/logger/lib/logger/backends/console.ex) backend in `config.exs`:

```elixir
config :logger,
  backends: [StathamLogger]
```

2. Add `StathamLogger.ExceptionCapturePlug` to `endpoint.ex` before `use Phoenix.Endpoint`.
```elixir
defmodule MyApp.Endpoint
  use StathamLogger.ExceptionCapturePlug
  use Phoenix.Endpoint, otp_app: :my_app
  # ...
end
```

3. Configure `StathamLogger`:

```elixir
config :logger, StathamLogger,
  metadata: :all,
  sanitize_options: [
    filter_keys: {:discard, ~w(password other_sensitive_key)},
    max_string_size: 100
  ]
```
Given this configuration, logged medatada will be sanitized:
- `password` and `other_sensitive_key` values replaced with `"[FILTERED]"`
- string values truncated to 100 characters

## Dynamic configuration
```elixir
iex> require Logger
iex> Logger.remove_backend(:console)
iex> Logger.add_backend(StathamLogger)
iex> Logger.configure_backend(StathamLogger, metadata: :all)
```

## Usage
```elixir
iex> Logger.metadata(metadata_field_1: "metadata_value_1")
iex> Logger.debug("hello")

# Output
{"file":"/some_file.ex","function":"say_hello/0","line":67,"logger":{"thread_name":"#PID<0.222.0>","method_name":"HelloModule.say_hello/0"},"message":"hello","metadata_field_1":"metadata_value_1","mfa":["HelloModule","say_hello",0],"module":"HelloModule","pid":"#PID<0.222.0>","syslog":{"hostname":"mb","severity":"debug","timestamp":"2021-10-07T10:20:17.902Z"}}
```

## Overwrite log level per invocation using StathamLogger groups

1. Configure groups
```elixir
config :logger, level: :info

config :logger, StathamLogger,
  groups: %{
    detailed_logs: [
      level: :debug
    ]
  }
```

2. Use group
```elixir
Logger.metadata(statham_logger_group: :detailed_logs)

# message is logged, because :detailed_logs level (:debug) overwrites :logger level (:info)
Logger.debug("hello")
```

4. Store things like current user (`logger_context.user`) and request details (`logger_context.http`) in Logger metadata under `logger_context` key.
`StathamLogger` looks in `logger_context` to set standard attributes values (see `StathamLogger.DatadogFormatter` for details).


## Extending functionality

See the `StathamLogger.Loggable` documentation.

## StathamLogger -> Datadog integration setup:

### Datadog integration: Install Agent
- install Datadog agent https://docs.datadoghq.com/agent/
- start agent `datadog-agent start`
- start agent gui `datadog-agent launch-gui`
- see Status->Collector page of GUI to confirm `datadog-agent` is working correctly
- see Status->General->AgentInfo page of GUI for configuration paths (`Config File`, `Conf.d Path` etc.)

### Datadog integration: APM
1. Update Datadog `Config File`, or in GUI Settings:
```yaml
api_key: [develpment api key from https://app.datadoghq.com/organization-settings/api-keys]
apm_config:
  enabled: true
```
2. In your app, make sure tracing is enabled
3. Change `MyApp.Tracer.Adapter.adapter_opts()` to `MyApp.Tracer.Adapter.adapter_opts(verbose: true)` in `MyApp.Tracer` module
4. Run in iex:
```elixir
1..10
|> Enum.map(fn i ->
  Task.async(fn ->
    MyApp.Tracer.start_trace("span_name#{i}", service: :my_app_dev, type: :custom)
    Process.sleep(5_000)
    MyApp.Tracer.finish_trace()
  end)
end)
|> Enum.map(&Task.await(&1, :infinity))
```
5. Observe traces received by [Datadog](https://app.datadoghq.com/apm/traces)

### Datadog integration: Logs
In staging/production Datadog Agent is using output of `:stdout`.
In development writing/reading logs to/from file should be used instead.

1. Enable logs in Datadog `Config File`, or in  GUI Settings:
```yaml
api_key: [develpment api key from https://app.datadoghq.com/organization-settings/api-keys]
logs_enabled: true
```
2. Follow the [custom log collection setup](https://docs.datadoghq.com/agent/logs/?tab=tailfiles#custom-log-collection):
- in `Conf.d Path` directory, create `<CUSTOM_LOG_SOURCE>.d` directory
- inside `<CUSTOM_LOG_SOURCE>.d`, create `conf.yaml` file:
```yaml
logs:
  - type: file
    path: <CUSTOM_PATH>.log
    service: custom-service
    source: custom-source
```
3. Start your app that has `statham_logger` dependency, and is using StathamLogger Logger backend with `mix phx.server > <CUSTOM_PATH>.log`
4. Start Datadog Agent `datadog-agent start`
5. Generate some Logs in your app
6. Observe logs received by Datadog Agent: `datadog-agent stream-logs`
7. Observe logs received by [Datadog](https://app.datadoghq.com/logs/livetail)
8. To see all logs, filter Live Tail by host, for example (https://app.datadoghq.com/logs/livetail?query=host%3Amb)

## Documentation
Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/statham_logger](https://hexdocs.pm/statham_logger).
