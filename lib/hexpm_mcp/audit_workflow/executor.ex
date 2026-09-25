defmodule HexpmMcp.AuditWorkflow.Executor do
  @moduledoc "Restartable read-only audit execution through the existing application domain path."
  @behaviour Snodo.Extensions.Tasks.WorkExecutor

  alias HexpmMcp.AuditWorkflow.Tool
  alias Snodo.Cancellation
  alias Snodo.Error
  alias Snodo.Extensions.Tasks.Work

  @limitations [
    "Completed means a report was produced, not a safe-package verdict.",
    "Only direct dependencies are inspected; no lockfile or resolved dependency graph is audited.",
    "OSV queries are package-name based, not matched against installed dependency versions.",
    "Unavailable owner or OSV data can yield no warning in the existing domain audit.",
    "Registry data may be cached; raw upstream responses and vulnerability IDs are not retained.",
    "Restart recovery may re-read changed upstream data; collection is not an atomic source snapshot."
  ]

  @impl true
  def execute(
        %Work{
          type: "tools/call",
          input: %{"name" => "durable_package_audit", "arguments" => args}
        } =
          work,
        cancellation,
        _state
      ) do
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()

    with :ok <- Tool.validate(args),
         :ok <- active(cancellation),
         {:ok, audit} <- HexpmMcp.audit_dependencies(args["name"], args["version"]),
         :ok <- active(cancellation) do
      report = %{
        "reportVersion" => 1,
        "idempotencyKey" => work.idempotency_key,
        "requestedRelease" => args,
        "collectionStartedAt" => started_at,
        "collectionFinishedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "sources" => ["Hex release/package/owner metadata", "OSV package-name advisory query"],
        "limitations" => @limitations,
        "observations" => Snodo.JSONValue.encodable!(audit)
      }

      {:completed,
       %{
         "resultType" => "complete",
         "content" => [
           %{
             "type" => "text",
             "text" =>
               "Advisory report produced for #{args["name"]} #{args["version"]}; " <>
                 "#{audit.total_warnings} warning(s). This is not a safety verdict."
           }
         ],
         "isError" => false,
         "structuredContent" => report
       }}
    else
      {:error, %Error{} = error} -> failed(error)
      {:error, :not_found} -> failed(Error.invalid_params("Requested package release not found"))
      {:error, _reason} -> failed(Error.internal("Audit report could not be produced"))
    end
  end

  def execute(%Work{}, _cancellation, _state),
    do: failed(Error.invalid_params("Unsupported durable audit descriptor"))

  defp active(cancellation) do
    if Cancellation.cancelled?(cancellation), do: {:error, :cancelled}, else: :ok
  end

  defp failed(error), do: {:failed, Error.to_json_rpc(error), error.message}
end
