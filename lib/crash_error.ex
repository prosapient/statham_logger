defmodule StathamLogger.CrashError do
  defexception [:message, :kind]

  def exception(%{__exception__: true, __struct__: struct} = exception) do
    %StathamLogger.CrashError{message: Exception.format_banner(:error, exception), kind: inspect(struct)}
  end

  def exception({:nocatch, reason}) do
    %StathamLogger.CrashError{message: Exception.format_banner(:throw, reason, []), kind: :throw}
  end

  def exception(reason) do
    %StathamLogger.CrashError{message: Exception.format_banner(:exit, reason, []), kind: :exit}
  end
end
