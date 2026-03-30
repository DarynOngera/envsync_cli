defmodule EnvsyncCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :envsync_cli,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      escript: escript(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {EnvsyncCli.Application, []}
    ]
  end

  defp escript do
    [
      main_module: EnvsyncCli.CLI,
      name: "envsync",
      comment: "EnvSync — environment secret synchronisation tool"
    ]
  end

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},
      # JSON
      {:jason, "~> 1.4"},
      # OS keychain access
      {:keyring, "~> 0.1"},
      # CLI argument parsing (built-in, but owl for pretty output)
      {:owl, "~> 0.12"}
    ]
  end

  defp aliases do
    [
      build: ["deps.get", "escript.build"],
      reinstall: ["escript.build", "cmd cp envsync /usr/local/bin/envsync"]
    ]
  end
end
