defmodule StathamLogger.LoggableStructWithKeep do
  @derive {StathamLogger.Loggable, filter_keys: {:keep, [:name, :phone_number]}}

  defstruct [:name, :password, :phone_number]
end
