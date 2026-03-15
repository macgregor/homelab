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

## Technical Reference

For panel type identifiers, JSON configuration, data format gotchas (multi-frame problem, working patterns), variable syntax, plugin configuration, and all other technical details, see [Grafana Dashboards Reference](grafana-dashboards.md).
