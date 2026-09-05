# Projections PDF export through MCP

`export_projections_report` generates the same dashboard and three financial
statements as the Projections page. It uses the existing authenticated `/mcp`
connection, including its OAuth and operator-managed machine access requirements.
It does not introduce a public route or change authentication scope requirements.

Input: `{"history_months": 1}`. Omission defaults to one completed calendar month;
set it to `3` for a three-month lookback. Integers from 1 through 120 are accepted.
No user, family, account, destination or arbitrary URL parameter is accepted.
Calculations retain the authenticated user's account access restrictions.

The returned object contains `filename`, `mime_type` (`application/pdf`),
`content_base64`, `byte_size`, `sha256`, `as_of`, `history_months`, `period_start`
and `period_end`. Dates are ISO 8601. Decode the base64 directly into a binary
attachment and verify its length, PDF signature and checksum. Do not print the
base64 or put report contents in execution logs. Exports over 5 MiB fail.

The historical statements use completed months. Balances and forecasts describe
the generation date, matching the Projections page; this is not a historical
as-of export. The tool generates in memory and sends no email, saves no files,
and changes no financial records. Generation can be retried after a transient
failure. Delivery retries and duplicate prevention belong to the caller.

For the monthly n8n workflow, schedule the first day of each month in the chosen
timezone, keep `history_months` editable, and call this tool with existing MCP
credentials stored in n8n's encrypted credential store. Allow up to 120 seconds
for generation. Stop on JSON-RPC errors, MCP `isError`, invalid PDF bytes or a
mismatching reporting period. Send only the verified PDF through the configured
Gmail credential, and record the delivery receipt rather than report contents.
