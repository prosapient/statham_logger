defmodule StathamLogger.MixProject do
  use Mix.Project

  def project do
    [
      app: :statham_logger,
      version: "0.1.0",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      deps: deps(),
      docs: [extras: ["README.md"]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    """
    Elixir Logger backend with Datadog integration and extensible Jason formatting
    """
  end

  defp package do
    [
      licenses: ["Apache 2"],
      links: %{
        GitHub: "https://github.com/prosapient/statham_logger"
      }
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:ex_doc, "~> 0.24", only: :dev}
    ]
  end
end
