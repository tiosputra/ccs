# knowledge/

The cross-service knowledge graph: `memory.jsonl`, kept by the `memory` MCP server
(`@modelcontextprotocol/server-memory`) and read and written through the
`knowledge-ops` skill.

It holds what is true *across* the services and outlives any one task — which service
owns a table, who publishes and who consumes an event, how a provider behaves — as
entities, relations between them, and dated observations. A task's own story stays
in `docs/<date>_<task>/`; code structure stays in the code-review graphs.

A provider's own published spec — an OpenAPI file, say — sits beside it in
`vendors/<provider>-<api>.yaml`, and the provider's entity in the graph names the
path, so a search for the provider finds the spec.

Like `docs/`, it describes the private services, so only this README is tracked; each
machine builds its own. `.claude/scripts/graph.sh mcp` writes the server into the
gitignored `.mcp.json`, with this directory's absolute path.
