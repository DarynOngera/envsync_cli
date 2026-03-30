defmodule EnvsyncCli.RepoIdentity do
  @moduledoc """
  Resolves and normalizes local GitHub repository identity as `owner/repo`.
  """

  @owner_repo_regex ~r/^[a-z0-9_.-]+\/[a-z0-9_.-]+$/

  def resolve_local_repo do
    case System.cmd("git", ["remote", "get-url", "origin"], stderr_to_stdout: true) do
      {output, 0} ->
        normalize_repo(output)

      {_output, _exit_code} ->
        {:error, :git_remote_not_found}
    end
  rescue
    _error -> {:error, :git_not_available}
  end

  def normalize_repo(input) when is_binary(input) do
    input
    |> String.trim()
    |> strip_prefix()
    |> strip_suffix()
    |> normalize_owner_repo()
  end

  def normalize_repo(_), do: {:error, :invalid_repo}

  defp strip_prefix("git@github.com:" <> rest), do: rest
  defp strip_prefix("https://github.com/" <> rest), do: rest
  defp strip_prefix("http://github.com/" <> rest), do: rest
  defp strip_prefix("ssh://git@github.com/" <> rest), do: rest
  defp strip_prefix(value), do: value

  defp strip_suffix(value) do
    value
    |> String.trim_trailing("/")
    |> String.trim_trailing(".git")
  end

  defp normalize_owner_repo(value) do
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
end
