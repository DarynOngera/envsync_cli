defmodule EnvsyncCli.Commands.Projects do
  alias EnvsyncCli.{Auth, Http}

  def run(_args, _opts) do
    with {:ok, _}    <- Auth.ensure_authenticated(),
         {:ok, body} <- Http.get("/api/projects") do
      projects = body["projects"]

      if Enum.empty?(projects) do
        Owl.IO.puts([Owl.Data.tag("  No projects assigned yet.", :yellow)])
      else
        Owl.IO.puts("\n")
        Enum.each(projects, fn p ->
          Owl.IO.puts([
            Owl.Data.tag("  #{p["name"]}", :cyan),
            Owl.Data.tag("  #{p["description"] || ""}", :light_black)
          ])
        end)
        Owl.IO.puts("\n")
      end
    else
      {:error, :unauthorized} ->
        Owl.IO.puts([Owl.Data.tag("✗ Session expired. Run: envsync auth login", :red)])
      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Failed: #{inspect(reason)}"])
    end
  end
end
