defmodule EnvsyncCli.CLI do
  @moduledoc """
  Entry point for the envsync escript binary.
  Routes top-level commands to their handler modules.
  """

  alias EnvsyncCli.Commands

  def main(argv) do
    {opts, args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          project:  :string,
          template: :string,
          env:      :string,
          help:     :boolean
        ],
        aliases: [
          p: :project,
          h: :help
        ]
      )

    if Keyword.get(opts, :help) do
      print_help()
    else
      route(args, opts)
    end
  end

  #  Routing 

  defp route(["auth" | rest],     opts), do: Commands.Auth.run(rest, opts)
  defp route(["whoami" | _],      opts), do: Commands.Whoami.run([], opts)
  defp route(["projects" | _],    opts), do: Commands.Projects.run([], opts)
  defp route(["check" | _],       opts), do: Commands.Check.run([], opts)
  defp route(["sync" | _],        opts), do: Commands.Sync.run([], opts)
  defp route(["help" | _],        _opts), do: print_help()
  defp route([],                  _opts), do: print_help()
  defp route([unknown | _],       _opts) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Unknown command: #{unknown}"])
    Owl.IO.puts("Run `envsync help` to see available commands.\n")
    exit({:shutdown, 1})
  end

  # Help 

  defp print_help do
    Owl.IO.puts("""

    envsync — environment secret synchronisation

    USAGE
      envsync <command> [options]

    COMMANDS
      auth login                          Authenticate with GitHub
      auth logout                         Clear stored session token
      whoami                              Show current authenticated identity
      projects                            List projects you have access to
      check                               Diff .env.example against local .env
      sync --project <name>               Fetch and write missing secrets

    OPTIONS
      --project, -p    Project name (required for sync)
      --template       Path to .env.example  (default: .env.example)
      --env            Path to .env          (default: .env)
      --help, -h       Show this help

    EXAMPLES
      envsync auth login
      envsync check
      envsync sync --project my_app
      envsync sync --project my_app --env .env.local

    """)
  end
end
