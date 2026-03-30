defmodule EnvsyncCli.ProjectState do
  @moduledoc """
  Persists per-project sync metadata.
  Currently stores the last seen backend `server_version` for each project.
  """

  alias EnvsyncCli.Config

  @state_file "project_state.json"

  def get_version(project) when is_binary(project) do
    with {:ok, state} <- read_state() do
      case Map.get(state, project) do
        value when is_integer(value) and value >= 0 -> {:ok, value}
        value when is_binary(value) -> parse_binary_version(value)
        _ -> :not_found
      end
    end
  end

  def put_version(project, version)
      when is_binary(project) and is_integer(version) and version >= 0 do
    with {:ok, state} <- read_state() do
      state
      |> Map.put(project, version)
      |> write_state()
    end
  end

  def clear do
    write_state(%{})
  end

  defp parse_binary_version(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> :not_found
    end
  end

  defp read_state do
    case File.read(state_path()) do
      {:ok, body} -> decode_state(body)
      {:error, :enoent} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_state(body) do
    case Jason.decode(body) do
      {:ok, %{} = state} -> {:ok, state}
      {:ok, _other} -> {:ok, %{}}
      {:error, _reason} -> {:ok, %{}}
    end
  end

  defp write_state(%{} = state) do
    File.mkdir_p!(Config.state_dir())
    File.write!(state_path(), Jason.encode!(state))
    File.chmod!(state_path(), 0o600)
    :ok
  end

  defp state_path do
    Path.join(Config.state_dir(), @state_file)
  end
end
