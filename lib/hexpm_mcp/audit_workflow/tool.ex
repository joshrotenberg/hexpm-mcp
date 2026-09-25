defmodule HexpmMcp.AuditWorkflow.Tool do
  @moduledoc "Exact-version audit descriptor admission; executions belong to the durable executor."
  use MCP.Tool.Simple,
    name: "durable_package_audit",
    description:
      "Produce a durable advisory report for a package release; requires Tasks support.",
    additional_properties: false

  alias HexpmMcp.AuditWorkflow.Store
  alias MCP.Error

  argument("name", :string,
    required: true,
    min_length: 1,
    max_length: 128,
    pattern: "^[a-z][a-z0-9_]*$"
  )

  argument("version", :string,
    required: true,
    min_length: 1,
    max_length: 128,
    description: "An exact semantic version, never a version requirement or latest."
  )

  @doc false
  def task_policy(params, context) do
    # Tasks middleware runs before the router's schema check. Invalid requests
    # continue synchronously to call/2 so they cannot create durable work first.
    if admit(Map.get(params, "arguments", %{}), context) == :ok, do: :required, else: :sync
  end

  @doc false
  def validate(%{"name" => name, "version" => version} = arguments)
      when map_size(arguments) == 2 and is_binary(name) and is_binary(version) do
    if byte_size(name) <= 128 and Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, name) and
         byte_size(version) <= 128 and match?({:ok, _version}, Version.parse(version)) do
      :ok
    else
      {:error, Error.invalid_params("Expected a Hex package name and exact semantic version")}
    end
  end

  def validate(_arguments),
    do: {:error, Error.invalid_params("Exactly name and version are required")}

  @impl true
  def call(arguments, context) do
    with :ok <- admit(arguments, context) do
      {:error, Error.internal("Durable audit requires the configured task executor")}
    end
  end

  defp admit(arguments, context) do
    if Store.authenticated?(context) do
      validate(arguments)
    else
      {:error,
       %Error{
         code: -32_003,
         kind: :authorization,
         message: "Trusted tenant authentication required"
       }}
    end
  end
end
