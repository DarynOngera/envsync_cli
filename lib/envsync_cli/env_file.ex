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
              [key, value] ->
                case normalize_key(key) do
                  "" -> acc
                  normalized_key -> Map.put(acc, normalized_key, String.trim(value))
                end

              _ ->
                acc
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
        "" -> true
        _ -> false
      end
    end)
  end

  @doc """
  Merges fetched secrets into the local .env file.

  Options:
  - `overwrite: true` updates existing key values (used for rotated secrets)
  - `overwrite: false` keeps existing values and only appends missing keys

  Returns `{:ok, %{added: [...], updated: [...]}}`.
  """
  def merge(secrets, path \\ ".env", opts \\ []) when is_map(secrets) do
    overwrite? = Keyword.get(opts, :overwrite, false)

    with {:ok, existing_content} <- read_existing_content(path) do
      existing_lines = lines_from_content(existing_content)

      {updated_lines, added_keys, updated_keys} =
        Enum.reduce(secrets, {existing_lines, [], []}, fn {key, value}, {lines, added, updated} ->
          key_regex = ~r/^\s*#{Regex.escape(key)}\s*=/
          replacement = "#{key}=#{value}"

          case Enum.find_index(lines, &Regex.match?(key_regex, &1)) do
            nil ->
              {lines ++ [replacement], [key | added], updated}

            idx ->
              current = Enum.at(lines, idx)

              cond do
                overwrite? and current != replacement ->
                  {List.replace_at(lines, idx, replacement), added, [key | updated]}

                true ->
                  {lines, added, updated}
              end
          end
        end)

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content_from_lines(updated_lines))
      File.chmod!(path, 0o600)

      {:ok, %{added: Enum.reverse(added_keys), updated: Enum.reverse(updated_keys)}}
    end
  end

  # Private

  defp read_existing_content(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, reason}
    end
  end

  defp comment_or_blank?(""), do: true
  defp comment_or_blank?("#" <> _rest), do: true
  defp comment_or_blank?(_), do: false

  defp extract_key(line) do
    case String.split(line, "=", parts: 2) do
      [key | _] ->
        case normalize_key(key) do
          "" -> nil
          normalized_key -> normalized_key
        end

      _ ->
        nil
    end
  end

  defp normalize_key(key) do
    key
    |> String.trim()
    |> String.replace(~r/^export\s+/, "")
    |> String.trim()
  end

  defp lines_from_content(""), do: []

  defp lines_from_content(content) do
    content
    |> String.split("\n", trim: false)
    |> drop_trailing_empty_line()
  end

  defp drop_trailing_empty_line([]), do: []

  defp drop_trailing_empty_line(lines) do
    case List.last(lines) do
      "" -> List.delete_at(lines, -1)
      _ -> lines
    end
  end

  defp content_from_lines([]), do: ""
  defp content_from_lines(lines), do: Enum.join(lines, "\n") <> "\n"
end
