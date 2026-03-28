defmodule EnvsyncCli.Http do
  @moduledoc """
  Thin wrapper around Req for all backend API calls.
  Automatically attaches the Bearer token and CLI version headers.
  All functions return {:ok, body_map} or {:error, reason}.
  """

  alias EnvsyncCli.{Config, TokenStore}

  def get(path) do
    with {:ok, token} <- TokenStore.get() do
      path
      |> Config.api_url()
      |> Req.get(headers: auth_headers(token))
      |> handle_response()
    else
      {:error, :not_found} -> {:error, :not_authenticated}
    end
  end

  def post(path, body) do
    with {:ok, token} <- TokenStore.get() do
      path
      |> Config.api_url()
      |> Req.post(json: body, headers: auth_headers(token))
      |> handle_response()
    else
      {:error, :not_found} -> {:error, :not_authenticated}
    end
  end

  def get_public(path) do
    path
    |> Config.api_url()
    |> Req.get()
    |> handle_response()
  end

  #  Private functions

  defp auth_headers(token) do
    [
      {"authorization",  "Bearer #{token}"},
      {"x-cli-version",  Config.cli_version()},
      {"content-type",   "application/json"}
    ]
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 401}}) do
    {:error, :unauthorized}
  end

  defp handle_response({:ok, %Req.Response{status: 403}}) do
    {:error, :forbidden}
  end

  defp handle_response({:ok, %Req.Response{status: 400, body: body}}) do
    {:error, {:bad_request, body}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:unexpected, status, body}}
  end

  defp handle_response({:error, exception}) do
    {:error, {:network, exception}}
  end
end
