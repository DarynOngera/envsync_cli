defmodule EnvsyncCli.TokenStore do
  @moduledoc """
  Persists and retrieves the JWT using the OS keychain.
  Falls back to a config file at ~/.config/envsync/token
  if the keychain is unavailable (e.g. headless Linux).
  """

  alias EnvsyncCli.Config

  @fallback_dir Path.expand("~/.config/envsync")
  @fallback_file Path.join(@fallback_dir, "token")

  def get do
    case keychain_get() do
      {:ok, token} -> {:ok, token}
      {:error, _} -> file_get()
    end
  end

  def put(token) do
    case keychain_put(token) do
      :ok -> :ok
      {:error, _} -> file_put(token)
    end
  end

  def delete do
    keychain_delete()
    file_delete()
    :ok
  end

  # Keychain

  defp keychain_get do
    try do
      case safe_keyring_call(:get, [Config.keyring_service(), Config.keyring_token_key()]) do
        nil -> {:error, :not_found}
        {:error, _} = error -> error
        token -> {:ok, token}
      end
    rescue
      _ -> {:error, :keychain_unavailable}
    catch
      :exit, _ -> {:error, :keychain_unavailable}
    end
  end

  defp keychain_put(token) do
    try do
      case safe_keyring_call(:set, [Config.keyring_service(), Config.keyring_token_key(), token]) do
        {:error, _} = error -> error
        _ -> :ok
      end
    rescue
      _ -> {:error, :keychain_unavailable}
    catch
      :exit, _ -> {:error, :keychain_unavailable}
    end
  end

  defp keychain_delete do
    try do
      _ = safe_keyring_call(:delete, [Config.keyring_service(), Config.keyring_token_key()])
      :ok
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end

  defp safe_keyring_call(function_name, args) do
    arity = length(args)

    if function_exported?(Keyring, function_name, arity) do
      apply(Keyring, function_name, args)
    else
      {:error, :keychain_unavailable}
    end
  end

  # File fallback

  defp file_get do
    case File.read(@fallback_file) do
      {:ok, token} -> {:ok, String.trim(token)}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp file_put(token) do
    File.mkdir_p!(@fallback_dir)
    File.write!(@fallback_file, token)
    File.chmod!(@fallback_file, 0o600)
    :ok
  end

  defp file_delete do
    File.rm(@fallback_file)
    :ok
  end
end
