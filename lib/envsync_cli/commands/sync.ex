defmodule EnvsyncCli.Commands.Sync do
  alias EnvsyncCli.{Auth, Http, EnvFile}

  def run(args, opts) do
    project       = extract_project(args, opts)
    template_path = Keyword.get(opts, :template, ".env.example")
    env_path      = Keyword.get(opts, :env,      ".env")

    unless project do
      Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Project name required. Usage: envsync sync --project <name>"])
      exit({:shutdown, 1})
    end

    with {:ok, _}             <- Auth.ensure_authenticated(),
         {:ok, template_keys} <- EnvFile.read_template(template_path),
         {:ok, local_env}     <- EnvFile.read_local(env_path),
         missing              = EnvFile.missing_keys(template_keys, local_env),
         :ok                  <- abort_if_nothing_to_sync(missing),
         {:ok, body}          <- fetch_secrets(project, missing),
         {:ok, written}       <- EnvFile.merge(body["secrets"], env_path) do

      print_sync_result(written, body["missing"] || [], env_path)
    else
      :nothing_to_sync ->
        Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Everything already in sync."])

      {:error, :template_not_found} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), ".env.example not found in current directory."])

      {:error, :unauthorized} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Session expired. Run: envsync auth login"])

      {:error, :forbidden} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Access denied for project: #{project}"])

      {:error, {:bad_request, body}} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Bad request: #{body["error"]}"])

      {:error, {:network, reason}} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Cannot reach backend: #{inspect(reason)}"])

      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Sync failed: #{inspect(reason)}"])
    end
  end

  #  Private 

  defp extract_project(args, opts) do
    Keyword.get(opts, :project) ||
      Enum.find_value(args, fn
        "--project=" <> name -> name
        _                   -> nil
      end)
  end

  defp abort_if_nothing_to_sync([]),      do: :nothing_to_sync
  defp abort_if_nothing_to_sync(_missing), do: :ok

  defp fetch_secrets(project, missing_keys) do
    Owl.IO.puts([
      Owl.Data.tag("→ ", :cyan),
      "Fetching #{length(missing_keys)} key(s) for project ",
      Owl.Data.tag(project, :cyan),
      "..."
    ])

    Http.post("/api/sync", %{
      project:      project,
      missing_keys: missing_keys,
      cli_version:  EnvsyncCli.Config.cli_version()
    })
  end

  defp print_sync_result(written, backend_missing, env_path) do
    Owl.IO.puts("\n")

    if Enum.empty?(written) do
      Owl.IO.puts([Owl.Data.tag("✓ ", :green), "No new keys written."])
    else
      Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Written to #{env_path}:"])
      Enum.each(written, fn key ->
        Owl.IO.puts([Owl.Data.tag("    + #{key}", :green)])
      end)
    end

    unless Enum.empty?(backend_missing) do
      Owl.IO.puts([Owl.Data.tag("\n  Keys not found in backend:", :yellow)])
      Enum.each(backend_missing, fn key ->
        Owl.IO.puts([Owl.Data.tag("    ? #{key}", :yellow)])
      end)
    end

    Owl.IO.puts("\n")
  end
end
