defmodule EnvsyncCli.Commands.Projects do
  alias EnvsyncCli.{Auth, Http}

  def run(args, opts) do
    case args do
      [] -> list()
      ["list"] -> list()
      ["create"] -> create(opts)
      ["reverify"] -> reverify(opts)
      _ -> print_usage()
    end
  end

  defp list do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, body} <- Http.get("/api/projects") do
      projects = body["projects"]

      if Enum.empty?(projects) do
        Owl.IO.puts([Owl.Data.tag("  No projects assigned yet.", :yellow)])
      else
        Owl.IO.puts("\n")

        Enum.each(projects, fn p ->
          repo_suffix =
            case p["repo_full_name"] do
              nil -> ""
              repo -> "  repo=#{repo}"
            end

          Owl.IO.puts([
            Owl.Data.tag("  #{p["name"]}", :cyan),
            Owl.Data.tag("  #{p["description"] || ""}#{repo_suffix}", :light_black)
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

  defp create(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, name} <- require_opt(opts, :name, "--name"),
         {:ok, repo} <- require_opt(opts, :repo, "--repo"),
         {:ok, body} <-
           Http.post("/api/projects", %{
             name: name,
             repo: repo,
             description: normalize_optional(Keyword.get(opts, :description))
           }) do
      project = body["project"] || %{}

      Owl.IO.puts([
        Owl.Data.tag("✓ ", :green),
        "Project created: ",
        Owl.Data.tag(project["name"] || name, :cyan),
        "  repo=",
        project["repo_full_name"] || repo
      ])
    else
      {:error, :missing_option} ->
        :error

      {:error, {:bad_request, body}} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), body["error"] || "bad request"])

      {:error, {:unprocessable_entity, body}} ->
        print_validation_error(body)

      {:error, :unauthorized} ->
        Owl.IO.puts([Owl.Data.tag("✗ Session expired. Run: envsync auth login", :red)])

      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Failed: #{inspect(reason)}"])
    end
  end

  defp reverify(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, body} <- Http.post("/api/projects/#{uri(project)}/reverify", %{}) do
      payload = body["project"] || %{}

      Owl.IO.puts([
        Owl.Data.tag("✓ ", :green),
        "Project repo re-verified: ",
        Owl.Data.tag(payload["name"] || project, :cyan),
        "  repo=",
        payload["repo_full_name"] || "unknown"
      ])
    else
      {:error, :missing_option} ->
        :error

      {:error, :forbidden} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Admin access required for this action."])

      {:error, {:unprocessable_entity, body}} ->
        print_validation_error(body)

      {:error, :unauthorized} ->
        Owl.IO.puts([Owl.Data.tag("✗ Session expired. Run: envsync auth login", :red)])

      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Failed: #{inspect(reason)}"])
    end
  end

  defp require_opt(opts, key, label) do
    case Keyword.get(opts, key) do
      nil ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Missing required option #{label}"])
        {:error, :missing_option}

      "" ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Missing required option #{label}"])
        {:error, :missing_option}

      value ->
        {:ok, value}
    end
  end

  defp normalize_optional(nil), do: nil
  defp normalize_optional(""), do: nil
  defp normalize_optional(value), do: value
  defp uri(value), do: URI.encode(to_string(value))

  defp print_validation_error(
         %{
           "error" => "repo must be a valid GitHub repository reference"
         } = body
       ) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), validation_message(body)])
  end

  defp print_validation_error(%{"error" => "repo verification failed"} = body) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), validation_message(body)])
  end

  defp print_validation_error(body) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), validation_message(body)])
  end

  @doc false
  def validation_message(%{"error" => "repo must be a valid GitHub repository reference"}) do
    "repo must be a valid GitHub repository reference. Use one of: owner/repo, " <>
      "https://github.com/owner/repo(.git), or git@github.com:owner/repo.git"
  end

  def validation_message(%{
        "error" => "repo verification failed",
        "details" => %{"reason" => reason}
      }) do
    case reason do
      "missing_token" ->
        "backend missing ENVSYNC_GITHUB_VERIFY_TOKEN (set it and restart backend)"

      "unauthorized" ->
        "verify token lacks access to this repo"

      "not_found" ->
        "repo not found or verify token cannot see it"

      "unreachable" ->
        "cannot reach GitHub API from backend"

      _ ->
        "repo verification failed (reason: #{reason})"
    end
  end

  def validation_message(body) do
    body["error"] || "validation failed"
  end

  defp print_usage do
    Owl.IO.puts("""

    Projects commands:
      envsync projects
      envsync projects list
      envsync projects create --name <project-name> --repo <owner/repo> [--description <text>]
      envsync projects reverify --project <project-name>

    """)
  end
end
