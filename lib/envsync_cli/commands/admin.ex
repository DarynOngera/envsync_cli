defmodule EnvsyncCli.Commands.Admin do
  alias EnvsyncCli.{Auth, Http}

  def run(args, opts) do
    case args do
      ["members", "list"] ->
        members_list(opts)

      ["members", "add"] ->
        members_add(opts)

      ["members", "role"] ->
        members_role(opts)

      ["members", "remove"] ->
        members_remove(opts)

      ["sync-status"] ->
        sync_status(opts)

      ["secrets", "set"] ->
        secrets_set(opts)

      ["secrets", "delete"] ->
        secrets_delete(opts)

      _ ->
        print_usage()
        exit({:shutdown, 1})
    end
  end

  # Members

  defp members_list(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, body} <- Http.get("/api/projects/#{uri(project)}/members") do
      members = body["members"] || []

      Owl.IO.puts("\n")
      Owl.IO.puts([Owl.Data.tag("Project: ", :light_black), project])

      if Enum.empty?(members) do
        Owl.IO.puts([Owl.Data.tag("  No members found.", :yellow)])
      else
        Enum.each(members, &print_member/1)
      end

      Owl.IO.puts("\n")
      :ok
    else
      error -> handle_error(error)
    end
  end

  defp members_add(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, github_login} <- require_opt(opts, :github_login, "--github-login"),
         role <- Keyword.get(opts, :role, "member"),
         {:ok, body} <-
           Http.post("/api/projects/#{uri(project)}/members", %{
             github_login: github_login,
             role: role
           }) do
      member = body["member"] || %{}
      Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Member assigned successfully."])
      print_member(member)
      :ok
    else
      error -> handle_error(error)
    end
  end

  defp members_role(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, member_id} <- require_opt(opts, :member_id, "--member-id"),
         {:ok, role} <- require_opt(opts, :role, "--role"),
         {:ok, body} <-
           Http.patch("/api/projects/#{uri(project)}/members/#{uri(member_id)}", %{role: role}) do
      Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Member role updated."])
      print_member(body["member"] || %{})
      :ok
    else
      error -> handle_error(error)
    end
  end

  defp members_remove(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, member_id} <- require_opt(opts, :member_id, "--member-id"),
         {:ok, _} <- Http.delete("/api/projects/#{uri(project)}/members/#{uri(member_id)}") do
      Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Member removed."])
      :ok
    else
      error -> handle_error(error)
    end
  end

  # Sync status

  defp sync_status(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, body} <- Http.get("/api/projects/#{uri(project)}/sync-status") do
      members = body["members"] || []
      server_version = body["server_version"] || 0

      Owl.IO.puts("\n")

      Owl.IO.puts([
        Owl.Data.tag("Project: ", :light_black),
        body["project"] || project,
        Owl.Data.tag("  server_version=", :light_black),
        to_string(server_version)
      ])

      if Enum.empty?(members) do
        Owl.IO.puts([Owl.Data.tag("  No members found.", :yellow)])
      else
        Enum.each(members, &print_member_sync_status/1)
      end

      Owl.IO.puts("\n")
      :ok
    else
      error -> handle_error(error)
    end
  end

  # Secrets

  defp secrets_set(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, key} <- require_opt(opts, :key, "--key"),
         {:ok, value} <- require_opt(opts, :value, "--value"),
         body <- build_secret_set_payload(opts, value),
         {:ok, response} <- Http.put("/api/projects/#{uri(project)}/secrets/#{uri(key)}", body) do
      Owl.IO.puts([
        Owl.Data.tag("✓ ", :green),
        "Secret stored: ",
        key,
        Owl.Data.tag("  server_version=", :light_black),
        to_string(response["server_version"])
      ])

      :ok
    else
      error -> handle_error(error)
    end
  end

  defp secrets_delete(opts) do
    with {:ok, _} <- Auth.ensure_authenticated(),
         {:ok, project} <- require_opt(opts, :project, "--project"),
         {:ok, key} <- require_opt(opts, :key, "--key"),
         {:ok, response} <- Http.delete("/api/projects/#{uri(project)}/secrets/#{uri(key)}") do
      Owl.IO.puts([
        Owl.Data.tag("✓ ", :green),
        "Secret deleted: ",
        key,
        Owl.Data.tag("  server_version=", :light_black),
        to_string(response["server_version"])
      ])

      :ok
    else
      error -> handle_error(error)
    end
  end

  # Helpers

  defp build_secret_set_payload(opts, value) do
    case Keyword.get(opts, :description) do
      nil -> %{value: value}
      "" -> %{value: value}
      description -> %{value: value, description: description}
    end
  end

  defp print_member(member) do
    dev = member["developer"] || %{}

    Owl.IO.puts([
      "  ",
      Owl.Data.tag(dev["github_login"] || "unknown", :cyan),
      "  role=",
      member["role"] || "member",
      "  active=",
      to_string(dev["active"]),
      "  id=",
      member["id"] || "-"
    ])
  end

  defp print_member_sync_status(member) do
    stale? = member["stale"] == true

    status_tag =
      if stale? do
        Owl.Data.tag("stale", :yellow)
      else
        Owl.Data.tag("fresh", :green)
      end

    Owl.IO.puts([
      "  ",
      Owl.Data.tag(member["github_login"] || "unknown", :cyan),
      "  status=",
      status_tag,
      "  last_synced_version=",
      to_string(member["last_synced_version"] || 0),
      "  role=",
      member["role"] || "member"
    ])
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

  defp handle_error({:error, :missing_option}), do: :error

  defp handle_error({:error, :unauthorized}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Session expired. Run: envsync auth login"])
    :error
  end

  defp handle_error({:error, :forbidden}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Admin access required for this action."])
    :error
  end

  defp handle_error({:error, :not_found}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Resource not found."])
    :error
  end

  defp handle_error({:error, {:bad_request, body}}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Bad request: #{body["error"]}"])
    :error
  end

  defp handle_error({:error, {:unprocessable_entity, body}}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Validation failed: #{body["error"]}"])
    :error
  end

  defp handle_error({:error, {:network, reason}}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Cannot reach backend: #{inspect(reason)}"])
    :error
  end

  defp handle_error({:error, reason}) do
    Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Request failed: #{inspect(reason)}"])
    :error
  end

  defp uri(value), do: URI.encode(to_string(value))

  defp print_usage do
    Owl.IO.puts("""

    Admin commands:
      envsync admin members list --project <name>
      envsync admin members add --project <name> --github-login <login> [--role member|admin]
      envsync admin members role --project <name> --member-id <id> --role <member|admin>
      envsync admin members remove --project <name> --member-id <id>
      envsync admin sync-status --project <name>
      envsync admin secrets set --project <name> --key <KEY> --value <VALUE> [--description <text>]
      envsync admin secrets delete --project <name> --key <KEY>

    """)
  end
end
