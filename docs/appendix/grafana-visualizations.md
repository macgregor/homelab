---
name: grafana-visualizations
description: >
  Load when building or modifying Grafana dashboards. Covers visualization
  selection, design principles, panel types, plugin configs, and data format
  gotchas for Prometheus/VictoriaMetrics datasources.
categories: [reference, grafana, dashboards]
tags: [visualization, panels, plugins, promql, transforms]
related_docs:
  - docs/appendix/grafana-dashboards.md
  - docs/appendix/victoriametrics-queries.md
complexity: intermediate
---

# Grafana Visualization Reference

## Choosing a Visualization

Don't default to time series for everything. Start with what question the user is trying to answer, then pick the visualization that answers it most directly.

### By question type

| Question | Best visualization | Why |
|----------|-------------------|-----|
| "Is it getting better or worse?" | Time series | Shows trend direction over time |
| "How does X compare to Y right now?" | Bar chart, Bar gauge | Side-by-side comparison of current values |
| "What's the current state?" | Stat, Gauge | Single prominent number with context |
| "What proportion is each part?" | Pie chart, Treemap | Shows relative size of categories |
| "Where is time being spent?" | Stacked bar, Treemap, State timeline | Shows composition and relative weight |
| "What's the distribution?" | Histogram, Heatmap | Shows spread, outliers, clustering |
| "Are there patterns by time of day/week?" | Hourly heatmap, Heatmap | 2D pattern detection across calendar dimensions |
| "What depends on what?" | Node graph, Diagram | Shows relationships and dependencies |
| "What happened in sequence?" | State timeline, Logs | Shows order of events and state transitions |
| "Which items need attention?" | Table with thresholds, Bar gauge | Sorted list with visual severity indicators |
| "What's the hierarchy?" | Treemap | Shows nested groupings with relative sizes |
| "How do two metrics correlate?" | XY Chart | Scatter plot reveals correlation patterns |

### By data shape

| Data shape | Good options | Avoid |
|------------|-------------|-------|
| Single value | Stat, Gauge | Time series (wastes space) |
| Few categories (2-7) | Pie chart, Bar chart | Table (harder to compare visually) |
| Many categories (8+) | Bar gauge, Table, Treemap | Pie chart (too many slices) |
| Ranked list | Bar gauge, Table with color | Pie chart (no rank ordering) |
| Time series, one metric | Time series, Trend | Bar gauge (loses time dimension) |
| Time series, many metrics | Time series with legend, Stacked bars | Individual stat panels (too many) |
| Hierarchical | Treemap | Flat bar chart (loses hierarchy) |
| Min/max/avg envelope | Time series with overrides | Separate panels for each |
| Success/failure ratio | Pie chart, Stat with threshold colors | Time series (unless tracking trend) |
| Log data | Logs panel | Table (loses expandability) |

### Combining panels effectively

- **Summary stat row + detail charts below**: stat panels at top for at-a-glance numbers, time series below for trends. The stat sparkline shows if the number is trending up/down.
- **Side-by-side comparison**: put related panels next to each other at equal width. "Success Rate" next to "Active Pipelines" lets you correlate activity with outcomes.
- **Overview + drill-down**: use variables/dropdowns to filter all panels simultaneously. The same panel shows aggregate data when "All" is selected and specific data when filtered.
- **Collapsible rows**: group detail panels in collapsed rows so the dashboard isn't overwhelming. Users expand what they need.
- **Tables for investigation, charts for monitoring**: tables with links are for clicking into specific items. Charts are for spotting patterns without reading individual values.
- **Color as a signal**: use threshold colors consistently (green=good, yellow=warning, red=bad). Don't use color decoratively -- every color should mean something.

### Anti-patterns

- **Dashboard of nothing but time series**: if every panel is a line chart, consider whether some questions are better answered by a stat, bar gauge, or table.
- **Too many panels**: more than ~12 panels on one page causes information overload. Use rows, collapsible sections, or separate dashboards.
- **Redundant panels**: if two panels show the same data differently (e.g. a success rate time series AND a success rate stat), keep the one that answers the question better and remove the other.
- **Unfiltered high-cardinality**: showing 200 time series on one chart is noise. Use `topk()`, filter variables, or aggregate before displaying.
- **Using time series for non-temporal data**: if the x-axis isn't time, don't use a time series panel. Use bar chart, XY chart, or table instead.

## Visualization Design Principles

### Information density

Maximize the data-ink ratio: every visual element should encode data. Remove anything that doesn't help the reader extract meaning.

**Remove:**
- Background fills and decorative gradients
- Excessive gridlines (keep only enough to anchor the eye -- or none if the trend shape is what matters)
- Redundant axis labels (if the panel title says "Success Rate (%)", the y-axis label "percent" adds nothing)
- Legends that repeat what's already obvious from panel titles or single-series charts
- Borders and boxes around panels (Grafana's transparent background mode is cleaner)

**Keep:**
- Thresholds (they provide context without adding separate panels)
- Annotations for deployments/incidents (they explain anomalies in-place)
- Sparklines in stat panels (they add trend context to a single number for free)

**Practical rule:** if you hide an element and the panel still communicates the same information, the element was noise.

### Cognitive load

A person glancing at a dashboard should know if things are OK within 5 seconds. Everything else is secondary.

**Pre-attentive attributes** -- the visual properties the brain processes before conscious thought: color saturation, size, position, orientation. Use these for the most critical signals:
- Red/amber/green threshold coloring on stat panels = instant health read
- Larger panels for more important metrics
- Top-left position for the single most important indicator (reading gravity)

**Reduce interpretation work:**
- Show rates and percentages, not raw counts that require mental math
- Use consistent units across related panels (don't mix seconds and milliseconds)
- Name panels as questions or plain-language descriptions ("CPU Usage %" not "cpu_usage_idle inverse")
- If a panel requires a paragraph of explanation to interpret, the visualization is wrong

**Panel count discipline:** more than ~12 visible panels on a single screen causes scanning fatigue. Use collapsible rows to keep the default view focused.

### Progressive disclosure

Structure dashboards as an inverted pyramid:

1. **Layer 1 -- Health summary** (visible without scrolling): stat panels with threshold colors answering "is everything OK?" One row, 3-5 panels max.
2. **Layer 2 -- Trends**: time series panels showing whether things are getting better or worse. Answers "what changed?"
3. **Layer 3 -- Breakdown**: bar charts, pie charts, tables showing composition. Answers "where is the problem?"
4. **Layer 4 -- Investigation** (collapsed by default): detailed tables with links, log panels, high-cardinality views. Answers "why?"

Users should never scroll past broken things to find out that things are broken. If the top row is green, they stop. If it's red, they scroll down to find out why.

### Comparison and context

A number without context is meaningless. "47 failures" means nothing. "47 failures, up from 12 last week" is actionable.

**Always provide baselines:**
- Stat panels: use sparklines (`graphMode: "area"`) to show whether the current value is normal
- Time series: add threshold lines for SLO targets or expected baselines
- Use `$__range` to make stats time-aware -- show the value for the selected time window, not all-time

**Comparison techniques:**
- Side-by-side panels at equal width for A/B comparison
- Dual Y-axis (sparingly) when two related metrics have different scales
- Delta/change indicators on stat panels (`orientation: "horizontal"` with color mode)
- "Last period" overlays on time series (shift query by `$__range` to compare current vs previous period)

### Color discipline

Color is a scarce resource. Use it to encode meaning, never for decoration.

**Rules:**
- Limit to 3-5 distinct colors per dashboard. More than that and the color coding breaks down.
- Red = bad/failure/critical. Yellow/amber = warning/degraded. Green = good/healthy. Blue = informational/neutral. These mappings must be consistent across every panel and every dashboard.
- Never use color as the sole differentiator -- always pair with text labels, position, or shape. ~8% of men have color vision deficiency.
- Grafana's "classic palette" auto-assigns colors to series. Override it when the default assignment creates misleading associations (e.g., errors rendered in green).
- For multi-series time series, use color to distinguish but keep the palette muted. Reserve saturated colors for thresholds and alerts.
- Background color on stat panels is the strongest visual signal on a dashboard. Use it only for health-critical metrics with well-defined thresholds.

### Chart selection heuristics

When in doubt, ask: **"What comparison am I making?"**

| Comparison type | Chart | Grafana panel |
|----------------|-------|---------------|
| Change over time | Line/area chart | Time series |
| Current value vs threshold | Number with color | Stat with thresholds, Gauge |
| Ranking / relative magnitude | Sorted bars | Bar gauge (`displayMode: "basic"`) |
| Composition (parts of whole) | Proportional areas | Pie chart, Treemap |
| Distribution / frequency | Bucketed counts | Histogram, Heatmap |
| Correlation between two variables | Scatter plot | XY Chart |
| State changes over time | Horizontal bands | State timeline |
| Temporal patterns (day/hour) | 2D grid | Hourly heatmap plugin |
| Sequential events | Timestamped list | Logs panel |

**Tie-breakers:**
- If the exact value matters more than the shape, use stat or table.
- If the trend matters more than the exact value, use time series.
- If you need both, use stat with sparkline.
- When you have more than 7 categories, switch from pie to bar gauge or table.
- When you have more than 20 series on a time series panel, you need to aggregate, filter with `topk()`, or rethink the query.

### Dashboard layout patterns

**The inverted pyramid layout:**
```
Row 1: [Stat] [Stat] [Stat] [Stat]        <- health at a glance
Row 2: [--- Time series ---] [--- Time series ---]  <- trends
Row 3: [Bar gauge] [Pie] [Table]           <- breakdown
Row 4 (collapsed): [Detailed table with links]       <- investigation
```

**Layout rules:**
- Consistent panel heights within each row. Jagged heights create visual noise.
- Related panels adjacent horizontally (left-to-right reading order). Put cause next to effect.
- Full-width panels for time series that need resolution. Half-width for comparison pairs.
- Stat panels: use the narrowest width that fits the content (typically 4-6 grid units). A row of 4-6 stats is the ideal summary bar.
- Leave no orphan panels -- a single panel in a row looks like an afterthought.

**Row organization:**
- Name rows descriptively ("Build Health", "Failure Analysis", not "Row 1").
- Collapse detail rows by default. The dashboard should be useful without expanding anything.
- Keep the most important row un-collapsed and above the fold.

### Interactivity

**Template variables** replace separate dashboards. One dashboard with a `$namespace` variable is better than N dashboards per namespace.

**Variable design:**
- Use query-driven variables (populated from label values) so they stay current without maintenance.
- Include an "All" option with `includeAll: true` for aggregate views.
- Cascade variables when there's a hierarchy: selecting a repo filters the list of available branches.
- Use `multi: true` only when the panels actually support multi-value comparison. A stat panel showing one number can't usefully display "All" of 50 job types.

**Data links** connect panels into investigation workflows:
- Stat panel (red) -> click -> filtered time series dashboard showing when it went red
- Table row -> click -> external link to build logs or PR
- Time series annotation -> click -> incident details

**Practical rule:** if a user sees a problem on Dashboard A and has to manually open Dashboard B and re-enter the same filters, add a data link.

## Built-in Panels (Grafana 12.x)

- **Time series** -- line/bar/point charts over time. Data: time series. The default for trends. Supports stacking, dual Y-axis, thresholds, annotations. Min interval via `interval` field on targets.
- **Bar chart** -- categorical comparisons. Data: table or time series. Horizontal/vertical. Good for comparing named values. Not great for time-based data.
- **Stat** -- single value with optional sparkline. Data: any (reduces to one value). Use `graphMode: "area"` for sparkline. Good for KPIs at dashboard top. Use `reduceOptions.calcs` to pick aggregation.
- **Gauge** -- single value on a radial scale. Data: any. Good for utilization/capacity metrics with known min/max.
- **Bar gauge** -- horizontal/vertical bars for multiple values. Data: time series with `legendFormat` + `instant: true`. Each series becomes a named bar. Works great for leaderboards/rankings. Use `displayMode: "basic"` to avoid gradient washout.
- **Table** -- tabular data. Data: table format. Supports sorting, filtering, column links, cell coloring. Single instant query works. Multi-query tables are problematic (see Data Format section).
- **State timeline** -- horizontal bands showing state changes over time. Data: time series with discrete values. Good for showing when things were up/down/degraded. Alternative to Gantt for showing time ranges.
- **Status history** -- grid of status indicators over time. Data: time series. Like state timeline but more compact.
- **Histogram** -- distribution of values. Data: time series or table. Shows frequency distribution. Good for latency/duration distributions.
- **Heatmap** -- 2D density visualization. Data: time series. X=time, Y=buckets, color=count. Good for spotting patterns in high-cardinality data.
- **Pie chart** -- proportional breakdown. Data: time series with `legendFormat` + `instant: true`. Each series becomes a slice. Donut variant available. Use for success/failure ratios, category breakdowns.
- **Candlestick** -- OHLC financial-style chart. Data: time series with open/high/low/close fields. Could show min/avg/max envelopes but requires specific field naming.
- **Node graph** -- directed graph visualization. Data: two frames (nodes + edges). Good for dependency maps, service graphs. Requires specific schema with id/title/mainStat fields.
- **Traces** -- distributed tracing waterfall. Data: trace format (Jaeger/Tempo). Shows span hierarchy with timing.
- **Flame graph** -- profiling visualization. Data: flame graph format. Shows call stack hierarchy.
- **Geomap** -- geographic visualization. Data: table with lat/lon fields or geohash. Multiple layer types.
- **Canvas** -- freeform layout with data-driven elements. Data: any. Highly customizable but manual positioning. Good for custom status displays.
- **Trend** -- sparkline-only panel, no axes. Data: time series. Compact trend indicator.
- **XY Chart** -- scatter/bubble plots. Data: table with X and Y numeric columns. Good for correlation analysis.
- **Logs** -- log line display with expand/collapse. Data: log format (Loki/VictoriaLogs). Shows timestamps, labels, expandable details. Use with log datasources only.
- **Text** -- static markdown/HTML content. No data. Good for dashboard documentation, help panels.

## Popular Plugins

- **marcusolsson-treemap-panel** -- hierarchical area visualization. Maintained by Grafana Labs. Uses `separator` in `fieldConfig.defaults.custom.separator` (NOT `options`) to create hierarchy from path-formatted labels like `Parent/Child/Leaf`. Size by numeric field, color by thresholds. Click shows data links context menu, no click-to-zoom. Use `reduce` transform with `reducers: ["lastNotNull"]` to convert time series into table format the plugin needs.
- **marcusolsson-gantt-panel** -- task timeline bars. Unmaintained. Needs table with string (task name), time (start), time (end) columns. X-axis locked to dashboard time range -- bars outside the range are invisible. Field options (`textField`, `startField`, `endField`) must match post-transform column names. Consider State Timeline for simpler use cases.
- **jdbranham-diagram-panel** -- Mermaid.js diagrams (flowcharts, sequence diagrams, gantt charts). Diagram defined as static text in panel config. Metric series can color nodes by matching series alias to node ID. Good for architecture diagrams with live status.
- **volkovlabs-echarts-panel** -- Apache ECharts wrapper. Requires JavaScript code in panel config to build chart options. Extremely flexible -- can build any visualization ECharts supports. Use when nothing else works. Higher maintenance burden.
- **marcusolsson-hourly-heatmap-panel** -- day-of-week vs hour-of-day heatmap. Good for time-of-day pattern analysis (e.g. CI success rate by hour). Aggregates data into day/hour buckets automatically.

## Data Format Reference

### The Multi-Frame Problem

Prometheus instant queries with `format: "table"` return **one data frame per series**. Labels are frame metadata, NOT data columns. This is the root cause of most "No data" or "Configure your query" errors on non-timeseries panels.

**What fails:**
- Two instant table queries + `merge` transform expecting joined columns -- `merge` appends rows, doesn't join
- Table panel expecting `pr_number` as a column -- it's in frame metadata
- Treemap/Gantt expecting string + number columns from table format -- they see separate frames with only Time + Value

### Working Patterns

**Bar gauge / Pie chart** (simplest):
```
format: default (NOT table)
legendFormat: "{{label_name}}"
instant: true
```
Each series becomes a named value. No transforms needed.

**Treemap:**
```
format: default, legendFormat with / separator, instant: true
transform: reduce (reducers: ["lastNotNull"])
fieldConfig.defaults.custom.separator: "/"
```
The `reduce` transform collapses multi-frame time series into one table with `Field` (string) and `Last` (number) columns.

**Single-query table:**
```
format: table, instant: true
transform: merge (combines frames into one table with labels as columns)
transform: organize (rename/hide columns)
```
Works for ONE query. Labels become columns after merge.

**Multi-query table (e.g. total + passed counts):**
```
Single query using label_replace + or:
  label_replace(query_a, "metric", "total", "", "") or label_replace(query_b, "metric", "passed", "", "")
format: table, instant: true
transform: merge
transform: groupingToMatrix (columnField: "metric", rowField: "source", valueField: "Value")
```
Combines two metrics into one query with a `metric` label, then pivots into columns.

### Variable Queries: label_values vs query_result

`label_values(metric{filters}, label)` is the standard way to populate variable dropdowns, but it does not reliably scope results to the dashboard time range in VictoriaMetrics. The dropdown may show values from outside the visible window, leading to "No data" when users select them.

**Fix:** Use `query_result()` with `[$__range:]` to force time-range scoping:

```
query_result(group by (namespace) (count_over_time(kube_pod_status_phase{filters}[$__range:])))
```

Add a `regex` field to extract the label value: `/namespace="([^"]+)"/`

This ensures the dropdown only shows values with data in the visible time range.

**Multi-select in LogsQL:** Use `${var:pipe}` formatting to produce `val1|val2` for regex matching: `level:~"${level:pipe}"`. The `:pipe` format also works correctly when "All" is selected (outputs the `allValue`).

### VictoriaLogs Datasource Limitations

The `victoriametrics-logs-datasource` Grafana plugin only supports log queries. It does NOT route `| stats` pipe queries to VL's `stats_query` or `stats_query_range` endpoints. A query like `level:error | stats count() as errors` returns a single log entry with `errors: "38"` as a field, instead of a numeric value usable in stat/timeseries/bar panels.

**Implication:** Stat, timeseries, bar gauge, and table panels cannot use VL stats aggregations. Use the built-in log volume histogram in logs panels for volume-over-time visualization. For stats-based analytics, use VL's HTTP API directly or Grafana Explore.

The VL stats API endpoints work correctly and return Prometheus-compatible formats (`stats_query` returns `vector`, `stats_query_range` returns `matrix`), so this is a plugin limitation rather than a VL limitation.

### Grafana Variables in PromQL

| Variable | Value | Use |
|----------|-------|-----|
| `$__range` | Duration string (e.g. `7d`) | Subquery window: `[expr[$__range:]]` |
| `$__interval` | Auto-computed bucket size | Time series bucketing: `[expr[$__interval:]]` |
| `$__from` / `$__to` | Unix milliseconds | Anchoring synthetic timestamps |
| `$__range_s` | Range in seconds | Arithmetic in queries |
| `$variable` | Template variable value | Label matching: `{label=~"$var"}` |
| `${var:regex}` | Regex-escaped value | Empty textbox = empty string = matches nothing |

**Empty variable gotcha:** `${pr_number:regex}` with empty textbox produces `""` which matches only empty strings. Use `.*$pr_number.*` instead for optional filtering.

### Plugin Config: options vs fieldConfig

Plugin settings live in either `options` (panel-level) or `fieldConfig.defaults.custom` (field-level). Check the plugin's `types.ts` to know which.

| Plugin | Setting | Location |
|--------|---------|----------|
| Treemap | `separator` | `fieldConfig.defaults.custom` |
| Treemap | `tiling` | `options` |
| Gantt | `textField`, `startField`, `endField` | `options` |
| Bar gauge | `displayMode`, `orientation` | `options` |

### Python + Dashboard JSON

When generating dashboard JSON via Python, `$` signs in f-strings or regular strings get interpreted as escape sequences. This corrupts `$__range`, `$job_type` etc.

**Fix:** Use heredoc syntax to avoid string interpolation:
```python
# BAD -- $__range becomes garbled
expr = f"query[{dollar}__range:]"

# GOOD -- heredoc preserves $ literally
subprocess.run(['python3'], input='''
import json
expr = 'query[$__range:]'
''')
```

Or use `cat << 'PYEOF'` in bash (single-quoted delimiter prevents shell expansion).
