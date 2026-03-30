defmodule EnvsyncCli.Commands.Watch do
  alias EnvsyncCli.{Commands.Sync, Config}

  def run(args, opts) do
    project = Keyword.get(opts, :project)

    unless project do
      Owl.IO.puts([
        Owl.Data.tag("✗ ", :red),
        "Project name required. Usage: envsync watch --project <name>"
      ])

      exit({:shutdown, 1})
    end

    interval_seconds =
      normalized_interval(Keyword.get(opts, :interval, Config.watch_interval_seconds()))

    Owl.IO.puts([
      Owl.Data.tag("→ ", :cyan),
      "Watching project ",
      Owl.Data.tag(project, :cyan),
      " every ",
      to_string(interval_seconds),
      "s (Ctrl+C to stop)"
    ])

    loop(args, opts, interval_seconds)
  end

  defp loop(args, opts, interval_seconds) do
    _ = Sync.run(args, opts)
    Process.sleep(interval_seconds * 1_000)
    loop(args, opts, interval_seconds)
  end

  defp normalized_interval(value) when is_integer(value) and value > 0, do: value
  defp normalized_interval(_), do: Config.watch_interval_seconds()
end
