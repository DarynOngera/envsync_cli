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
          project: :string,
          name: :string,
          provider: :string,
          repo: :string,
          template: :string,
          env: :string,
          interval: :integer,
          login: :string,
          github_login: :string,
          role: :string,
          member_id: :string,
          key: :string,
          value: :string,
          description: :string,
          help: :boolean
        ],
        aliases: [
          p: :project,
          i: :interval,
          h: :help
        ]
      )

    if Keyword.get(opts, :help) do
      print_help()
    else
      route(args, opts)
    end
  end

  # Routing

  defp route(["auth" | rest], opts), do: Commands.Auth.run(rest, opts)
  defp route(["whoami" | _], opts), do: Commands.Whoami.run([], opts)
  defp route(["projects" | rest], opts), do: Commands.Projects.run(rest, opts)
  defp route(["check" | _], opts), do: Commands.Check.run([], opts)
  defp route(["sync" | _], opts), do: Commands.Sync.run([], opts)
  defp route(["watch" | _], opts), do: Commands.Watch.run([], opts)
  defp route(["admin" | rest], opts), do: Commands.Admin.run(rest, opts)
  defp route(["help" | _], _opts), do: print_help()
  defp route([], _opts), do: print_help()

  defp route([unknown | _], _opts) do
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
      auth login [--provider <name>]      Authenticate with GitHub/Bitbucket
      auth logout                         Clear stored session token
      whoami                              Show current authenticated identity
      projects                            List projects you have access to
      projects create --name <name> --repo <repo-ref> [--provider github|bitbucket] [--description <text>]
      projects reverify --project <name>  Re-verify project repo binding (admin)
      check                               Diff .env.example against local .env
      sync --project <name>               Publish local .env changes (admin) then sync
      watch --project <name>              Poll backend and auto-sync repeatedly

      admin members list --project <name>
      admin members add --project <name> --provider <provider> --login <login> [--role member|admin]
      admin members add --project <name> --github-login <login> [--role member|admin]
      admin members role --project <name> --member-id <id> --role <member|admin>
      admin members remove --project <name> --member-id <id>
      admin sync-status --project <name>
      admin secrets set --project <name> --key <KEY> --value <VALUE> [--description <text>]
      admin secrets delete --project <name> --key <KEY>

    OPTIONS
      --project, -p         Project name
      --name                Project name for creation
      --provider            Auth/member/project provider (github|bitbucket)
      --repo                Repo reference for project binding
      --template            Path to .env.example  (default: .env.example)
      --env                 Path to .env          (default: .env)
      --interval, -i        Watch poll interval seconds (default: 30)
      --login               Provider login for member assignment
      --github-login        GitHub login for member assignment
      --role                member/admin role value
      --member-id           Membership UUID
      --key                 Secret key name
      --value               Secret value
      --description         Optional secret description
      --help, -h            Show this help

    EXAMPLES
      envsync sync --project my_app
      envsync projects create --name my_app --repo myorg/my_app --provider github
      envsync auth login --provider bitbucket
      envsync watch --project my_app --interval 20
      envsync admin members list --project my_app
      envsync admin members add --project my_app --provider github --login alice
      envsync admin secrets set --project my_app --key API_KEY --value secret123

    """)
  end
end
