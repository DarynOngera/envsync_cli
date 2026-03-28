defmodule EnvsyncCli.Auth do
  @moduledoc """
  Manages the GitHub OAuth login flow.
  Opens a browser to the backend login URL, spins up a temporary local
  HTTP server to receive the JWT callback, then stores the token.
  """

  alias EnvsyncCli.{Config, TokenStore, Http}

  @timeout_ms 120_000

  def login do
    port  = Config.callback_port()
    url   = Config.login_url()

    Owl.IO.puts([Owl.Data.tag("→ ", :cyan), "Opening browser for GitHub login..."])
    open_browser(url)
    Owl.IO.puts([Owl.Data.tag("  Waiting for callback on port #{port}...", :light_black)])

    case await_callback(port) do
      {:ok, token} ->
        TokenStore.put(token)
        Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Authenticated successfully."])
        {:ok, token}

      {:error, :timeout} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Login timed out. Please try again."])
        {:error, :timeout}

      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Login failed: #{inspect(reason)}"])
        {:error, reason}
    end
  end

  def logout do
    TokenStore.delete()
    Owl.IO.puts([Owl.Data.tag("✓ ", :green), "Logged out. Token cleared."])
    :ok
  end

  def ensure_authenticated do
    case TokenStore.get() do
      {:ok, token} ->
        case Http.get("/api/whoami") do
          {:ok, _}              -> {:ok, token}
          {:error, :unauthorized} ->
            Owl.IO.puts([Owl.Data.tag("  Session expired. Re-authenticating...", :yellow)])
            TokenStore.delete()
            login()
        end

      {:error, :not_found} ->
        Owl.IO.puts([Owl.Data.tag("  No session found. Logging in...", :yellow)])
        login()
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp open_browser(url) do
    cmd =
      case :os.type() do
        {:unix, :darwin}  -> "open"
        {:unix, _}        -> "xdg-open"
        {:win32, _}       -> "start"
      end

    System.cmd(cmd, [url], stderr_to_stdout: true)
  end

  defp await_callback(port) do
    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, packet: :http])

    result =
      receive_with_timeout(listen_socket, @timeout_ms)

    :gen_tcp.close(listen_socket)
    result
  end

  defp receive_with_timeout(listen_socket, timeout) do
    task = Task.async(fn -> accept_and_extract(listen_socket) end)

    case Task.yield(task, timeout) do
      {:ok, result} -> result
      nil           ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp accept_and_extract(listen_socket) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    request        = read_request(socket)

    send_callback_response(socket)
    :gen_tcp.close(socket)

    extract_token_from_request(request)
  end

  defp read_request(socket) do
    read_request(socket, "")
  end

  defp read_request(socket, acc) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_request, _method, {:abs_path, path}, _vsn}} ->
        read_request(socket, to_string(path))

      {:ok, :http_eoh} ->
        acc

      {:ok, _other} ->
        read_request(socket, acc)

      {:error, _} ->
        acc
    end
  end

  defp send_callback_response(socket) do
    body = """
    <html><body>
    <h2>EnvSync — Authentication successful</h2>
    <p>You can close this window and return to your terminal.</p>
    </body></html>
    """

    response = """
    HTTP/1.1 200 OK\r\n\
    Content-Type: text/html\r\n\
    Content-Length: #{byte_size(body)}\r\n\
    Connection: close\r\n\
    \r\n\
    #{body}
    """

    :gen_tcp.send(socket, response)
  end

  defp extract_token_from_request(path) do
    uri    = URI.parse(path)
    params = URI.decode_query(uri.query || "")

    case Map.get(params, "token") do
      nil   -> {:error, :no_token_in_callback}
      token -> {:ok, token}
    end
  end
end
