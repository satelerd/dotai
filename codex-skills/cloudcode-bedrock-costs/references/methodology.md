# Local Cloud Code Cost Methodology

## Objective
Estimate Cloud Code Bedrock usage/cost from local transcript files on the machine where the analysis runs.

## Data source (local-only)
- `~/.claude/projects/**/*.jsonl`
- Each assistant entry includes:
  - `message.model`
  - `message.usage` (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`)
  - `timestamp`, `sessionId`, `cwd`

No AWS CLI, CloudTrail, CloudWatch, or Cost Explorer queries are used.

## Core logic
1. Discover all local transcript JSONL files under `projects/`.
2. Keep only assistant rows that contain `message.usage`.
3. Deduplicate invocations by `sessionId + message.id` to remove repeated logging rows.
4. Optionally filter by date range and workspace substring.
5. Estimate cost from tokens using model-family pricing assumptions:
   - Haiku: input 1.0 / output 5.0 USD per MTok
   - Sonnet: input 3.0 / output 15.0 USD per MTok
   - Opus: input 15.0 / output 75.0 USD per MTok
6. Apply cache modifiers:
   - cache write = 1.25x input rate
   - cache read = 0.10x input rate
7. Aggregate by day/model/workspace/session and render JSON/CSV/HTML/PDF.

## Plan-pressure correlation (USD 20 plans)
- Cloud Code Pro benchmark:
  - 10-40 prompts every 5 hours
  - ~40-80 usage hours per week (model-dependent)
  - Source: https://support.anthropic.com/es/articles/8324991-about-claude-pro-plans
- Codex Plus benchmark:
  - 30-150 messages every 5 hours (local Codex)
  - OpenAI mentions an additional shared weekly cap, without publishing exact number
  - Source: https://help.openai.com/en/articles/11750701-what-are-the-rate-limits-for-codex

The report computes:
- rolling 5h invocation pressure and exceed periods over low/high thresholds
- weekly equivalent hours under optimistic throughput assumptions
- proxy weekly pressure for Codex when the weekly cap is undisclosed

## Interpretation
- Values are **estimated** costs (not billing line items).
- Differences vs AWS invoice can come from regional pricing, taxes, support, credits, and model-price changes over time.
- The report is strongest for trend analysis, model mix, and local user behavior.
