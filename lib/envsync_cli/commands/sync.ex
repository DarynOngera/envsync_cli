defmodule EnvsyncCli.Commands.Sync do
  alias EnvsyncCli.{Auth, Http, EnvFile, ProjectState, Config}

  def run(args, opts) do
    project = extract_project(args, opts)
    template_path = Keyword.get(opts, :template, ".env.example")
    env_path = Keyword.get(opts, :env, ".env")

    unless project do
      Owl.IO.puts([
        Owl.Data.tag("✗ ", :red),
        "Project name required. Usage: envsync sync --project <name>"
      ])

      exit({:shutdown, 1})
    end

    with {:ok, template_keys} <- EnvFile.read_template(template_path),
         :ok <- ensure_non_empty_template(template_keys),
         {:ok, local_env} <- read_local_env(env_path),
         :ok <- sync_once(project, template_keys, local_env, env_path, retry?: true) do
      :ok
    else
      {:error, :template_not_found} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), ".env.example not found in current directory."])

      {:error, :empty_template} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), ".env.example contains no keys to sync."])

      {:error, {:network, reason}} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Cannot reach backend: #{inspect(reason)}"])

      {:error, {:bad_request, body}} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Bad request: #{body["error"]}"])

      {:error, :forbidden} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Access denied for project: #{project}"])

      {:error, {:local_env_read, reason}} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Could not read #{env_path}: #{inspect(reason)}"])

      {:error, {:partial_publish_forbidden, pushed_count}} ->
        Owl.IO.puts([
          Owl.Data.tag("✗ ", :red),
          "Publish stopped after #{pushed_count} key(s). Admin permission was lost mid-run."
        ])

      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Sync failed: #{inspect(reason)}"])
    end
  end

  # Private

  defp extract_project(args, opts) do
    Keyword.get(opts, :project) ||
      Enum.find_value(args, fn
        "--project=" <> name -> name
        _ -> nil
      end)
  end

  defp ensure_non_empty_template([]), do: {:error, :empty_template}
  defp ensure_non_empty_template(_keys), do: :ok

  defp read_local_env(env_path) do
    case EnvFile.read_local(env_path) do
      {:ok, local_env} -> {:ok, local_env}
      {:error, reason} -> {:error, {:local_env_read, reason}}
    end
  end

  defp sync_once(project, template_keys, local_env, env_path, retry?: retry?) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, publish_result} <- maybe_publish_local_env(project, template_keys, local_env),
         {:ok, body} <- fetch_secrets(project, template_keys),
         {:ok, merge_result} <- apply_sync_payload(body, env_path),
         :ok <- persist_project_version(project, body["server_version"]) do
      print_sync_result(publish_result, merge_result, body["missing"] || [], body, env_path)
      :ok
    else
      {:error, :unauthorized} when retry? ->
        Owl.IO.puts([
          Owl.Data.tag("  Session expired during sync. Re-authenticating...", :yellow)
        ])

        with {:ok, _token} <- Auth.login() do
          sync_once(project, template_keys, local_env, env_path, retry?: false)
        end

      {:error, :unauthorized} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Session expired. Run: envsync auth login"])
        {:error, :unauthorized}

      other ->
        other
    end
  end

  defp fetch_secrets(project, requested_keys) do
    payload = build_sync_payload(project, requested_keys, include_client_version?: true)

    Owl.IO.puts([
      Owl.Data.tag("→ ", :cyan),
      "Syncing ",
      Owl.Data.tag(project, :cyan),
      " (",
      to_string(length(requested_keys)),
      " key(s) declared in template)..."
    ])

    Http.post("/api/sync", payload)
  end

  defp fetch_backend_snapshot(project, requested_keys) do
    payload = build_sync_payload(project, requested_keys, include_client_version?: false)
    Http.post("/api/sync", payload)
  end

  defp build_sync_payload(project, requested_keys, opts) do
    payload = %{
      project: project,
      requested_keys: requested_keys,
      cli_version: Config.cli_version()
    }

    if Keyword.get(opts, :include_client_version?, true) do
      maybe_put_client_version(payload, project)
    else
      payload
    end
  end

  defp maybe_put_client_version(payload, project) do
    case ProjectState.get_version(project) do
      {:ok, version} -> Map.put(payload, :client_version, version)
      :not_found -> payload
      {:error, _reason} -> payload
    end
  end

  defp maybe_publish_local_env(project, template_keys, local_env) do
    local_template_values = extract_local_template_values(local_env, template_keys)
    local_count = map_size(local_template_values)

    if local_count == 0 do
      {:ok, %{local_keys: 0, changed_keys: 0, pushed_keys: 0, skipped_forbidden: false}}
    else
      with {:ok, snapshot} <- fetch_backend_snapshot(project, template_keys) do
        backend_secrets = snapshot["secrets"] || %{}
        changed_values = changed_local_values(local_template_values, backend_secrets)
        changed_count = map_size(changed_values)

        cond do
          changed_count == 0 ->
            {:ok,
             %{
               local_keys: local_count,
               changed_keys: 0,
               pushed_keys: 0,
               skipped_forbidden: false
             }}

          true ->
            push_changed_values(project, changed_values, local_count, changed_count)
        end
      end
    end
  end

  defp extract_local_template_values(local_env, template_keys) do
    Enum.reduce(template_keys, %{}, fn key, acc ->
      case Map.get(local_env, key) do
        nil -> acc
        "" -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp changed_local_values(local_template_values, backend_secrets) do
    Enum.reduce(local_template_values, %{}, fn {key, local_value}, acc ->
      if Map.get(backend_secrets, key) == local_value do
        acc
      else
        Map.put(acc, key, local_value)
      end
    end)
  end

  defp push_changed_values(project, changed_values, local_count, changed_count) do
    case do_push_changed_values(project, Map.to_list(changed_values), 0) do
      {:ok, pushed_count} ->
        {:ok,
         %{
           local_keys: local_count,
           changed_keys: changed_count,
           pushed_keys: pushed_count,
           skipped_forbidden: false
         }}

      {:forbidden, 0} ->
        {:ok,
         %{
           local_keys: local_count,
           changed_keys: changed_count,
           pushed_keys: 0,
           skipped_forbidden: true
         }}

      {:forbidden, pushed_count} ->
        {:error, {:partial_publish_forbidden, pushed_count}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_push_changed_values(_project, [], pushed_count), do: {:ok, pushed_count}

  defp do_push_changed_values(project, [{key, value} | rest], pushed_count) do
    case Http.put("/api/projects/#{uri(project)}/secrets/#{uri(key)}", %{value: value}) do
      {:ok, _body} ->
        do_push_changed_values(project, rest, pushed_count + 1)

      {:error, :forbidden} ->
        {:forbidden, pushed_count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_sync_payload(%{"up_to_date" => true}, _env_path) do
    {:ok, %{added: [], updated: []}}
  end

  defp apply_sync_payload(body, env_path) do
    EnvFile.merge(body["secrets"] || %{}, env_path, overwrite: true)
  end

  defp persist_project_version(_project, nil), do: :ok

  defp persist_project_version(project, version) when is_integer(version) and version >= 0 do
    ProjectState.put_version(project, version)
  end

  defp persist_project_version(project, version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} when parsed >= 0 -> ProjectState.put_version(project, parsed)
      _ -> :ok
    end
  end

  defp persist_project_version(_project, _version), do: :ok

  defp print_sync_result(publish_result, merge_result, backend_missing, body, env_path) do
    Owl.IO.puts("\n")
    print_publish_result(publish_result)

    if body["up_to_date"] == true do
      Owl.IO.puts([
        Owl.Data.tag("✓ ", :green),
        "Already up to date",
        maybe_version_suffix(body["server_version"])
      ])
    else
      print_added(merge_result.added, env_path)
      print_updated(merge_result.updated, env_path)

      if Enum.empty?(merge_result.added) and Enum.empty?(merge_result.updated) do
        Owl.IO.puts([
          Owl.Data.tag("✓ ", :green),
          "No file changes were needed",
          maybe_version_suffix(body["server_version"])
        ])
      else
        Owl.IO.puts([
          Owl.Data.tag("✓ ", :green),
          "Sync completed",
          maybe_version_suffix(body["server_version"])
        ])
      end
    end

    unless Enum.empty?(backend_missing) do
      Owl.IO.puts([Owl.Data.tag("\n  Keys not found in backend:", :yellow)])

      Enum.each(backend_missing, fn key ->
        Owl.IO.puts([Owl.Data.tag("    ? #{key}", :yellow)])
      end)
    end

    Owl.IO.puts("\n")
  end

  defp print_publish_result(%{local_keys: 0}) do
    Owl.IO.puts([
      Owl.Data.tag("! ", :yellow),
      "No local values found in .env for template keys. Nothing to publish."
    ])
  end

  defp print_publish_result(%{skipped_forbidden: true}) do
    Owl.IO.puts([
      Owl.Data.tag("! ", :yellow),
      "Local .env values found, but this account is not a project admin. Skipping publish."
    ])
  end

  defp print_publish_result(%{changed_keys: 0, local_keys: local_keys}) do
    Owl.IO.puts([
      Owl.Data.tag("✓ ", :green),
      "Local .env already matches backend for ",
      to_string(local_keys),
      " template key(s)."
    ])
  end

  defp print_publish_result(%{pushed_keys: pushed_keys, changed_keys: changed_keys})
       when pushed_keys > 0 do
    Owl.IO.puts([
      Owl.Data.tag("✓ ", :green),
      "Published ",
      to_string(pushed_keys),
      "/",
      to_string(changed_keys),
      " changed key(s) from local .env to backend."
    ])
  end

  defp print_added([], _env_path), do: :ok

  defp print_added(added_keys, env_path) do
    Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Added to #{env_path}:"])

    Enum.each(added_keys, fn key ->
      Owl.IO.puts([Owl.Data.tag("    + #{key}", :green)])
    end)
  end

  defp print_updated([], _env_path), do: :ok

  defp print_updated(updated_keys, env_path) do
    Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Updated in #{env_path}:"])

    Enum.each(updated_keys, fn key ->
      Owl.IO.puts([Owl.Data.tag("    ~ #{key}", :cyan)])
    end)
  end

  defp maybe_version_suffix(nil), do: ""
  defp maybe_version_suffix(version), do: " (server version #{version})"

  defp uri(value), do: URI.encode(to_string(value))
end
