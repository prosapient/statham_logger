# StathamLogger

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

2. Configure `StathamLogger`:

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

## Extending functionality

See the `StathamLogger.Loggable` documentation.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/statham_logger](https://hexdocs.pm/statham_logger).

