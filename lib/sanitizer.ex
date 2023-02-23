defmodule StathamLogger.Sanitizer do
  @doc """
  Filter metadata keys, apply `:sanitize_options`.
  """

  alias StathamLogger.Loggable

  @spec sanitize_metadata(map()) :: {map(), map()}
  def sanitize_metadata(metadata) when is_map(metadata) do
    config = config()
    filter_keys = Keyword.get(config, :metadata)
    options = Keyword.get(config, :sanitize_options)
    sanitized_metadata = sanitize_metadata(metadata, filter_keys, options)

    sanitized_metadata
  end

  @spec sanitize_metadata(map(), list(atom()) | :all, list({atom(), list(:atom)})) :: map()
  def sanitize_metadata(metadata, filter_keys, options) when is_map(metadata) do
    metadata
    |> take_metadata(filter_keys)
    |> Loggable.sanitize(options)
  end

  defp take_metadata(metadata, :all) do
    metadata
  end

  defp take_metadata(metadata, keys) do
    Map.take(metadata, keys)
  end

  defp config do
    Application.get_env(:logger, StathamLogger, [])
  end
end
