defmodule EnvsyncCli.Http do
  @moduledoc """
  Thin wrapper around Req for backend API calls.
  Automatically attaches the Bearer token and CLI version headers.
  All functions return {:ok, body_map} or {:error, reason}.
  """

  alias EnvsyncCli.{Config, TokenStore}

  def get(path), do: auth_request(:get, path)
  def post(path, body), do: auth_request(:post, path, json: body)
  def put(path, body), do: auth_request(:put, path, json: body)
  def patch(path, body), do: auth_request(:patch, path, json: body)
  def delete(path), do: auth_request(:delete, path)

  def get_public(path) do
    path
    |> Config.api_url()
    |> Req.get()
    |> handle_response()
  end

  # Private functions

  defp auth_request(method, path, req_opts \\ []) do
    with {:ok, token} <- TokenStore.get() do
      path
      |> Config.api_url()
      |> request(method, auth_headers(token), req_opts)
      |> handle_response()
    else
      {:error, :not_found} -> {:error, :not_authenticated}
    end
  end

  defp request(url, method, headers, req_opts) do
    Req.request([url: url, method: method, headers: headers] ++ req_opts)
  end

  defp auth_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"x-cli-version", Config.cli_version()},
      {"content-type", "application/json"}
    ]
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}
  defp handle_response({:ok, %Req.Response{status: 201, body: body}}), do: {:ok, body}
  defp handle_response({:ok, %Req.Response{status: 204}}), do: {:ok, %{}}

  defp handle_response({:ok, %Req.Response{status: 400, body: body}}),
    do: {:error, {:bad_request, body}}

  defp handle_response({:ok, %Req.Response{status: 401}}), do: {:error, :unauthorized}
  defp handle_response({:ok, %Req.Response{status: 403}}), do: {:error, :forbidden}
  defp handle_response({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}

  defp handle_response({:ok, %Req.Response{status: 422, body: body}}),
    do: {:error, {:unprocessable_entity, body}}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:unexpected, status, body}}

  defp handle_response({:error, exception}), do: {:error, {:network, exception}}
end
