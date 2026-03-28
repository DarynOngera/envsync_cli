defmodule EnvsyncCli.EnvFile do
  @moduledoc """
  Parses .env and .env.example files.
  Treats .env.example as the source of structural truth (keys only).
  Treats .env as the local state (key-value pairs).
  """

  @doc """
  Returns a list of key names from .env.example.
  Ignores comments and blank lines.
  """
  def read_template(path \\ ".env.example") do
    case File.read(path) do
      {:ok, content} ->
        keys =
          content
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&comment_or_blank?/1)
          |> Enum.map(&extract_key/1)
          |> Enum.reject(&is_nil/1)

        {:ok, keys}

      {:error, :enoent} ->
        {:error, :template_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns a map of key => value from the local .env file.
  Missing file is treated as empty — not an error.
  """
  def read_local(path \\ ".env") do
    case File.read(path) do
      {:ok, content} ->
        pairs =
          content
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&comment_or_blank?/1)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, "=", parts: 2) do
              [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
              _            -> acc
            end
          end)

        {:ok, pairs}

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the list of keys from .env.example that are
  absent or empty in the local .env.
  """
  def missing_keys(template_keys, local_env) do
    Enum.filter(template_keys, fn key ->
      case Map.get(local_env, key) do
        nil -> true
        ""  -> true
        _   -> false
      end
    end)
  end

  @doc """
  Merges fetched secrets into the local .env file.
  Only writes keys that are in the secrets map.
  Never overwrites keys that already have values.
  Creates the file if it does not exist.
  Sets file permissions to 0600.
  """
  def merge(secrets, path \\ ".env") do
    {:ok, existing} = read_local(path)

    new_entries =
      secrets
      |> Enum.reject(fn {key, _value} -> Map.has_key?(existing, key) end)
      |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
      |> Enum.join("\n")

    existing_content = if File.exists?(path), do: File.read!(path), else: ""

    updated =
      case {String.ends_with?(existing_content, "\n"), new_entries} do
        {_, ""}      -> existing_content
        {true,  _}   -> existing_content <> new_entries <> "\n"
        {false, _}   ->
          separator = if existing_content == "", do: "", else: "\n"
          existing_content <> separator <> new_entries <> "\n"
      end

    File.write!(path, updated)
    File.chmod!(path, 0o600)

    written_keys = Enum.map(new_entries |> String.split("\n"), fn line ->
      case String.split(line, "=", parts: 2) do
        [key, _] -> key
        _        -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))

    {:ok, written_keys}
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp comment_or_blank?(""),           do: true
  defp comment_or_blank?("#" <> _rest), do: true
  defp comment_or_blank?(_),            do: false

  defp extract_key(line) do
    case String.split(line, "=", parts: 2) do
      [key | _] -> String.trim(key)
      _         -> nil
    end
  end
end
