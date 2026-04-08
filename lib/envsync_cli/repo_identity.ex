defmodule EnvsyncCli.RepoIdentity do
  @moduledoc """
  Resolves and normalizes local repository identity into canonical
  provider-aware bindings.
  """

  @owner_repo_regex ~r/^[a-z0-9_.-]+\/[a-z0-9_.-]+$/
  @host_regex ~r/^[a-z0-9.-]+$/

  @spec resolve_local_repo_binding() ::
          {:ok, %{provider: String.t(), host: String.t(), full_name: String.t()}}
          | {:error, atom()}
  def resolve_local_repo_binding do
    case System.cmd("git", ["remote", "get-url", "origin"], stderr_to_stdout: true) do
      {output, 0} -> normalize_repo_binding(output)
      {_output, _exit_code} -> {:error, :git_remote_not_found}
    end
  rescue
    _error -> {:error, :git_not_available}
  end

  @doc """
  Backward-compatible helper returning only canonical `owner/repo`.
  """
  def resolve_local_repo do
    with {:ok, binding} <- resolve_local_repo_binding() do
      {:ok, binding.full_name}
    end
  end

  @spec normalize_repo_binding(binary()) ::
          {:ok, %{provider: String.t(), host: String.t(), full_name: String.t()}}
          | {:error, atom()}
  def normalize_repo_binding(input) when is_binary(input) do
    input
    |> String.trim()
    |> parse_host_and_path()
    |> normalize_binding()
  end

  def normalize_repo_binding(_), do: {:error, :invalid_repo}

  @doc """
  Backward-compatible normalization returning only canonical full name.
  """
  def normalize_repo(input) when is_binary(input) do
    with {:ok, binding} <- normalize_repo_binding(input) do
      {:ok, binding.full_name}
    end
  end

  def normalize_repo(_), do: {:error, :invalid_repo}

  defp parse_host_and_path(""), do: {:error, :invalid_repo}

  defp parse_host_and_path(value) do
    cond do
      Regex.match?(~r/^git@[^:]+:.+$/, value) ->
        [_, host, path] = Regex.run(~r/^git@([^:]+):(.+)$/, value)
        {:ok, {String.downcase(host), strip_suffix(path)}}

      Regex.match?(~r/^ssh:\/\/git@[^\/:]+(?::\d+)?\/.+$/, value) ->
        [_, host, path] = Regex.run(~r/^ssh:\/\/git@([^\/:]+)(?::\d+)?\/(.+)$/, value)
        {:ok, {String.downcase(host), strip_suffix(path)}}

      String.starts_with?(value, "https://") or String.starts_with?(value, "http://") ->
        case URI.parse(value) do
          %URI{host: nil} ->
            {:error, :invalid_repo}

          %URI{host: host, path: path} ->
            normalized_path =
              (path || "")
              |> String.trim_leading("/")
              |> strip_suffix()

            {:ok, {String.downcase(host), normalized_path}}
        end

      Regex.match?(@owner_repo_regex, String.downcase(value)) ->
        {:ok, {"github.com", strip_suffix(value)}}

      true ->
        {:error, :invalid_repo}
    end
  end

  defp normalize_binding({:ok, {host, path}}) do
    with :ok <- validate_host(host),
         {:ok, provider, normalized_path} <- normalize_provider_and_path(host, path),
         {:ok, full_name} <- normalize_owner_repo(normalized_path) do
      {:ok, %{provider: provider, host: host, full_name: full_name}}
    end
  end

  defp normalize_binding({:error, reason}), do: {:error, reason}

  defp normalize_provider_and_path("github.com", path), do: {:ok, "github", path}
  defp normalize_provider_and_path("bitbucket.org", path), do: {:ok, "bitbucket", path}

  defp normalize_provider_and_path(host, "scm/" <> rest) when is_binary(host),
    do: {:ok, "bitbucket", rest}

  defp normalize_provider_and_path(host, path) when is_binary(host),
    do: {:ok, infer_provider(host), path}

  defp infer_provider(host) do
    if String.contains?(host, "bitbucket") do
      "bitbucket"
    else
      "github"
    end
  end

  defp validate_host(host) when is_binary(host) do
    if host != "" and host =~ @host_regex do
      :ok
    else
      {:error, :invalid_repo}
    end
  end

  defp normalize_owner_repo(value) when is_binary(value) do
    case String.split(value, "/", parts: 3) do
      [owner, repo] ->
        canonical =
          [owner, repo]
          |> Enum.map(&String.downcase/1)
          |> Enum.join("/")

        if canonical =~ @owner_repo_regex do
          {:ok, canonical}
        else
          {:error, :invalid_repo}
        end

      _ ->
        {:error, :invalid_repo}
    end
  end

  defp strip_suffix(value) do
    value
    |> String.trim_trailing("/")
    |> String.trim_trailing(".git")
  end
end
