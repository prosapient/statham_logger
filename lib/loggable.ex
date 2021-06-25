defprotocol StathamLogger.Loggable do
  @moduledoc """
  Implement this protocol to remove confidential values or trim Logger output.
  """

  @doc """
  Built-in implementations handle only `sensitive_keys` and `max_string_size` options.
  Other options can be handled by custom `StathamLogger.Loggable` implementations.
  """
  @fallback_to_any true
  def sanitize(term, opts \\ [])
end

defimpl StathamLogger.Loggable, for: Any do
  def sanitize(%{__struct__: Ecto.Association.NotLoaded}, _), do: :not_loaded

  def sanitize(%_struct{} = data, opts) do
    if jason_implemented?(data) do
      data
    else
      data
      |> Map.from_struct()
      |> StathamLogger.Loggable.sanitize(opts)
    end
  end

  def sanitize(data, _), do: inspect(data)

  defp jason_implemented?(data) do
    impl = Jason.Encoder.impl_for(data)
    impl && impl != Jason.Encoder.Any
  end
end

defimpl StathamLogger.Loggable, for: Atom do
  def sanitize(data, _), do: data
end

defimpl StathamLogger.Loggable, for: Boolean do
  def sanitize(data, _), do: data
end

defimpl StathamLogger.Loggable, for: Integer do
  def sanitize(data, _), do: data
end

defimpl StathamLogger.Loggable, for: Map do
  def sanitize(map, opts) do
    sensitive_keys = Keyword.get(opts, :sensitive_keys) || []

    map
    |> Map.drop([:__struct__, :__meta__])
    |> Map.new(fn {key, value} ->
      if should_be_filtered(key, sensitive_keys) do
        {sanitize_map_key(key), "[FILTERED]"}
      else
        {sanitize_map_key(key), StathamLogger.Loggable.sanitize(value, opts)}
      end
    end)
  end

  defp sanitize_map_key(key) when is_binary(key) or is_atom(key) or is_number(key), do: key
  defp sanitize_map_key(key), do: inspect(key)

  defp should_be_filtered(field, sensitive_keys) do
    Enum.any?(sensitive_keys, fn key -> to_string(key) == to_string(field) end)
  end
end

defimpl StathamLogger.Loggable, for: BitString do
  @impl true
  def sanitize(string, opts) do
    max_string_size = Keyword.get(opts, :max_string_size)

    if string_valid?(string) do
      if max_string_size && String.length(string) > max_string_size do
        "#{String.slice(string, 0..(max_string_size - 1))}..."
      else
        string
      end
    else
      inspect(string)
    end
  end

  defp string_valid?(string), do: String.valid?(string) && String.printable?(string)
end

defimpl StathamLogger.Loggable, for: List do
  @impl true
  def sanitize(list, opts) do
    if Keyword.keyword?(list) do
      list
      |> Map.new()
      |> StathamLogger.Loggable.sanitize(opts)
    else
      list
      |> Enum.map(&StathamLogger.Loggable.sanitize(&1, opts))
    end
  end
end

defimpl StathamLogger.Loggable, for: Tuple do
  @impl true
  def sanitize(tuple, opts) do
    tuple
    |> Tuple.to_list()
    |> StathamLogger.Loggable.sanitize(opts)
  end
end
