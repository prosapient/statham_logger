defmodule StathamLogger.LoggableStructWithDiscard do
  @derive {StathamLogger.Loggable, filter_keys: {:discard, [:phone_number]}}

  defstruct [:name, :password, :phone_number]
end
