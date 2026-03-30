defmodule EnvsyncCli.Config do
  @moduledoc """
  Centralises all runtime configuration for the CLI.
  Values are read from environment variables with sensible local defaults.
  """

  @default_backend_url "http://localhost:4000"
  @default_callback_port 9292
  @default_watch_interval_seconds 30
  @default_state_dir Path.expand("~/.config/envsync")
  @keyring_service "envsync"
  @keyring_token_key "auth_token"
  @cli_version "0.1.0"

  def backend_url do
    System.get_env("ENVSYNC_BACKEND_URL") || @default_backend_url
  end

  def callback_port do
    System.get_env("ENVSYNC_CALLBACK_PORT")
    |> case do
      nil -> @default_callback_port
      value -> String.to_integer(value)
    end
  end

  def watch_interval_seconds do
    System.get_env("ENVSYNC_SYNC_INTERVAL")
    |> case do
      nil -> @default_watch_interval_seconds
      value -> parse_positive_int(value, @default_watch_interval_seconds)
    end
  end

  def state_dir do
    System.get_env("ENVSYNC_STATE_DIR") || @default_state_dir
  end

  def keyring_service, do: @keyring_service
  def keyring_token_key, do: @keyring_token_key
  def cli_version, do: @cli_version

  def login_url do
    "#{backend_url()}/auth/github"
  end

  def api_url(path) do
    "#{backend_url()}#{path}"
  end

  defp parse_positive_int(value, fallback) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end
end
