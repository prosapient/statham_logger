# StathamLogger

A backend for the Elixir [https://hexdocs.pm/logger/Logger.html](Logger) that:
- transforms logged [https://hexdocs.pm/logger/1.12/Logger.html#module-metadata](metadata), by hiding sensitive values and trimming long strings
- outputs JSON string, structured according to [Datadog attributest list](https://docs.datadoghq.com/logs/processing/attributes_naming_convention/#default-standard-attribute-list)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `statham_logger` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:statham_logger, "~> 0.1"}
  ]
end
```

## Configuration

1. Configure StathamLogger in `config.exs`. In this example `password` and `just_another_sensitive_key` will have corresponding value set to `[FILTERED]:

```elixir
config :logger, StathamLogger,
  metadata: :all,
  sanitize_options: [
    filter_keys: {:discard, ~w(password just_another_sensitive_key)},
    max_string_size: 100
  ]
```

2. Use `StathamLogger` Logger backend, instead of default [https://github.com/elixir-lang/elixir/blob/master/lib/logger/lib/logger/backends/console.ex](`Console`) backend

In `config.exs`:

```elixir
config :logger,
  backends: [StathamLogger],
  level: :warning
```

Or dynamically:

```elixir
require Logger
...
Logger.add_backend(StathamLogger)
```

## Extending functionality

See the `StathamLogger.Loggable` documentation.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/statham_logger](https://hexdocs.pm/statham_logger).

