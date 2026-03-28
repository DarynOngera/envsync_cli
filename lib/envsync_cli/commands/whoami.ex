defmodule EnvsyncCli.Commands.Whoami do
  alias EnvsyncCli.{Auth, Http}

  def run(_args, _opts) do
    with {:ok, _}    <- Auth.ensure_authenticated(),
         {:ok, body} <- Http.get("/api/whoami") do
      Owl.IO.puts([
        "\n",
        Owl.Data.tag("  GitHub login:  ", :light_black), "#{body["github_login"]}\n",
        Owl.Data.tag("  Email:         ", :light_black), "#{body["email"] || "(none)"}\n",
        Owl.Data.tag("  Active:        ", :light_black), "#{body["active"]}\n",
        Owl.Data.tag("  Last seen:     ", :light_black), "#{body["last_seen_at"] || "never"}\n"
      ])
    else
      {:error, :unauthorized} -> reauthenticate()
      {:error, reason}        -> print_error(reason)
    end
  end

  defp reauthenticate do
    Owl.IO.puts([Owl.Data.tag("  Session expired. Run: envsync auth login", :yellow)])
  end

  defp print_error(reason) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Could not fetch identity: #{inspect(reason)}"])
  end
end
