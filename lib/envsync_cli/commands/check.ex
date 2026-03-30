defmodule EnvsyncCli.Commands.Check do
  alias EnvsyncCli.EnvFile

  def run(_args, opts) do
    template_path = Keyword.get(opts, :template, ".env.example")
    env_path = Keyword.get(opts, :env, ".env")

    with {:ok, template_keys} <- EnvFile.read_template(template_path),
         {:ok, local_env} <- EnvFile.read_local(env_path) do
      missing = EnvFile.missing_keys(template_keys, local_env)

      total = length(template_keys)
      present = total - length(missing)

      Owl.IO.puts("\n")

      if Enum.empty?(missing) do
        Owl.IO.puts([
          Owl.Data.tag("✓ ", :green),
          "All #{total} keys present in #{env_path}"
        ])
      else
        Owl.IO.puts([
          Owl.Data.tag("  #{present}/#{total}", :cyan),
          " keys present — ",
          Owl.Data.tag("#{length(missing)} missing:\n", :yellow)
        ])

        Enum.each(missing, fn key ->
          Owl.IO.puts([Owl.Data.tag("    ✗ #{key}", :red)])
        end)
      end

      Owl.IO.puts("\n")
      if Enum.empty?(missing), do: :ok, else: {:missing, missing}
    else
      {:error, :template_not_found} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), ".env.example not found in current directory."])
        {:error, :template_not_found}

      {:error, reason} ->
        Owl.IO.puts([Owl.Data.tag("✗ ", :red), "Failed to read files: #{inspect(reason)}"])
        {:error, reason}
    end
  end
end
