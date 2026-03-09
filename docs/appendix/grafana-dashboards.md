---
name: grafana-dashboards
description: >
  Load this document when creating, editing, or troubleshooting Grafana dashboards.
  Covers dashboard JSON structure, panel types, PromQL/MetricsQL queries, variables,
  transformations, provisioning, and common pitfalls.
categories: [observability, visualization]
tags: [grafana, dashboards, promql, metricsql, panels, variables, provisioning]
related_docs:
  - docs/06-observability.md
complexity: intermediate
---

# Grafana Dashboards Reference

Concise working reference for generating and editing Grafana dashboard JSON. Not a tutorial — optimized for correct JSON output with links to official docs.

**Official documentation root:** https://grafana.com/docs/grafana/latest/

**Version note:** Written against Grafana 10.x+. The dashboard JSON schema evolves across versions. When working on dashboards, export an existing dashboard from the target instance to confirm the current schema shape, and fetch current docs if the deployed version has changed significantly.

---

## Table of Contents

1. [Critical Gotchas](#1-critical-gotchas)
2. [Dashboard JSON Model](#2-dashboard-json-model)
3. [Panel Types](#3-panel-types)
4. [Queries and Data Sources](#4-queries-and-data-sources)
5. [Variables (Templating)](#5-variables-templating)
6. [Transformations](#6-transformations)
7. [Thresholds, Overrides, and Mappings](#7-thresholds-overrides-and-mappings)
8. [Units and Colors](#8-units-and-colors)
9. [Provisioning](#9-provisioning)
10. [MetricsQL Differences](#10-metricsql-differences)
11. [Documentation Links](#11-documentation-links)

---

## 1. Critical Gotchas

### `id` must be `null` for provisioned/imported dashboards

The `id` field is database-generated. A numeric ID causes conflicts across instances. The `uid` (string, 8-40 chars) is the stable identifier.

### Panel IDs must be unique within a dashboard

Duplicate `panel.id` values cause silent rendering failures.

### `instant` vs `range` query type

Time series panels need range queries (`"instant": false`). Stat, gauge, and table panels typically use instant queries (`"instant": true`). Wrong query type produces empty panels.

### `percent` vs `percentunit`

`"unit": "percent"` expects values 0-100. `"unit": "percentunit"` expects values 0-1. Mismatching causes 100x display errors. See [Units and Colors](#8-units-and-colors).

### `$__rate_interval` does not expand in variable queries

`$__rate_interval` works in panel queries but is **not interpolated** in template variable query definitions. Use `$__interval` in variable queries instead.

### Threshold steps auto-sort

Steps sort highest to lowest automatically. First step must have `"value": null` (base color). Cannot be manually reordered.

### `graphTooltip` is dashboard-level, not per-panel

Set on the dashboard root: `0` = none (no sharing), `1` = shared crosshair, `2` = shared crosshair + tooltip. Per-panel tooltip mode is a separate `options.tooltip` config.

---

## 2. Dashboard JSON Model

### Minimal valid dashboard

```json
{
  "id": null,
  "uid": "my-dashboard-uid",
  "title": "My Dashboard",
  "description": "",
  "tags": [],
  "timezone": "browser",
  "editable": true,
  "graphTooltip": 0,
  "schemaVersion": 39,
  "version": 1,
  "refresh": "30s",
  "time": { "from": "now-6h", "to": "now" },
  "templating": { "list": [] },
  "annotations": { "list": [] },
  "panels": [],
  "links": []
}
```

### Top-level fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | int/null | Database-generated. Set `null` for provisioning. |
| `uid` | string | Stable identifier, 8-40 chars, unique per org |
| `title` | string | Dashboard name |
| `tags` | string[] | Categorization tags |
| `timezone` | string | `"browser"` or `"utc"` |
| `editable` | bool | Whether UI editing is allowed |
| `graphTooltip` | int | 0=none (no sharing), 1=shared crosshair, 2=shared crosshair+tooltip |
| `time` | object | `{"from": "now-6h", "to": "now"}` |
| `refresh` | string | Auto-refresh: `"5s"`, `"1m"`, `""` (off) |
| `schemaVersion` | int | JSON schema version (increments with Grafana releases) |
| `version` | int | Dashboard version (increments on each save) |
| `templating` | object | `{"list": [...]}` — template variables |
| `annotations` | object | `{"list": [...]}` — annotation queries (e.g., deployment markers on time series) |
| `panels` | array | Panel objects |
| `links` | array | Dashboard-level links |
| `description` | string | Dashboard description (optional) |

### Panel positioning

24-column grid layout:

```json
"gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 }
```

| Field | Range | Description |
|-------|-------|-------------|
| `w` | 1-24 | Width in columns. Full=24, half=12. |
| `h` | 1+ | Height in grid units |
| `x` | 0-23 | Column offset |
| `y` | 0+ | Row offset. Panels auto-sort by `y` then `x`. |

### Row panels

Rows group panels and support collapsing:

```json
{
  "type": "row",
  "title": "Section Name",
  "collapsed": false,
  "gridPos": { "h": 1, "w": 24, "x": 0, "y": 0 },
  "panels": []
}
```

When `collapsed: true`, child panels go inside the row's `panels` array. When `collapsed: false`, child panels are top-level siblings positioned below the row's `y`.

### Repeat panels

Panels can repeat dynamically for each value of a variable:

```json
{
  "type": "timeseries",
  "title": "CPU: $instance",
  "repeat": "instance",
  "repeatDirection": "h",
  "maxPerRow": 4,
  "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 }
}
```

- `repeat`: variable name (without `$`)
- `repeatDirection`: `"h"` (horizontal) or `"v"` (vertical)
- `maxPerRow`: max panels per row (horizontal repeat)

Rows can also repeat by setting `"repeat"` on a row panel.

### Dashboard links

```json
"links": [{
  "title": "Related Dashboard",
  "type": "dashboards",
  "tags": ["infrastructure"],
  "asDropdown": true,
  "includeVars": true,
  "keepTime": true
}]
```

Link types: `"dashboards"` (by tag match) or `"link"` (explicit URL). `includeVars` forwards current variable values. `keepTime` preserves the time range.

### `__inputs` and `__requires` (exported dashboards)

Dashboards exported from the Grafana UI include `__inputs` and `__requires` at the top level. These are metadata for the import process, not runtime config.

```json
{
  "__inputs": [{
    "name": "DS_VICTORIAMETRICS",
    "label": "VictoriaMetrics",
    "type": "datasource",
    "pluginId": "prometheus"
  }],
  "__requires": [
    { "type": "grafana", "id": "grafana", "name": "Grafana", "version": "10.0.0" },
    { "type": "datasource", "id": "prometheus", "name": "Prometheus", "version": "1.0.0" }
  ]
}
```

- `__inputs`: Declares datasource placeholders. Panels reference them via `"uid": "${DS_VICTORIAMETRICS}"`. On import, Grafana prompts the user to map each input to an existing datasource.
- `__requires`: Declares minimum versions of Grafana, datasource plugins, and panel plugins needed.

When provisioning dashboards via file (not the import UI), `__inputs` variables are **not resolved** — panels must use literal datasource UIDs or provisioned datasource names instead.

---

## 3. Panel Types

### Common type identifiers

| `"type"` value | Visualization |
|----------------|---------------|
| `timeseries` | Time series (line/bar/point). Default graph. Replaces deprecated `graph`. |
| `stat` | Single value + optional sparkline |
| `gauge` | Arc gauge with min/max |
| `bargauge` | Horizontal/vertical bar gauge |
| `table` | Tabular data |
| `barchart` | Categorical bar chart |
| `piechart` | Pie/donut chart |
| `heatmap` | 2D density heatmap |
| `state-timeline` | State changes over time |
| `status-history` | Historical status grid |
| `text` | Markdown/HTML content |
| `row` | Collapsible row grouping (not a visualization) |

Full list: https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/

Note: most type identifiers are lowercase, but some use camelCase (e.g., `nodeGraph`). Check the docs for the exact string.

### Time series (`timeseries`)

```json
{
  "type": "timeseries",
  "fieldConfig": {
    "defaults": {
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "linear",
        "fillOpacity": 10,
        "lineWidth": 2,
        "pointSize": 5,
        "stacking": { "mode": "none" },
        "spanNulls": false,
        "axisPlacement": "auto"
      },
      "unit": "bytes",
      "min": 0,
      "color": { "mode": "palette-classic" },
      "noValue": "N/A"
    }
  },
  "options": {
    "legend": { "displayMode": "list", "placement": "bottom", "calcs": [] },
    "tooltip": { "mode": "single", "sort": "none" }
  }
}
```

| Property | Valid values |
|----------|-------------|
| `drawStyle` | `"line"`, `"bars"`, `"points"` |
| `lineInterpolation` | `"linear"`, `"smooth"`, `"stepBefore"`, `"stepAfter"` |
| `fillOpacity` | 0-100 |
| `stacking.mode` | `"none"`, `"normal"`, `"percent"` |
| `spanNulls` | `false` (gap), `true` (connect), or number (max gap in ms) |
| `legend.displayMode` | `"list"`, `"table"`, `"hidden"` |
| `legend.placement` | `"bottom"`, `"right"` |
| `legend.calcs` | Array of calculation IDs shown in legend (e.g., `["mean", "max"]`) |
| `tooltip.mode` | `"single"`, `"all"`, `"hidden"` |

### Stat (`stat`)

```json
{
  "type": "stat",
  "options": {
    "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false },
    "colorMode": "value",
    "graphMode": "area",
    "textMode": "auto",
    "orientation": "auto"
  }
}
```

| Option | Values |
|--------|--------|
| `colorMode` | `"none"`, `"value"`, `"background_solid"`, `"background_gradient"` |
| `graphMode` | `"none"` (value only), `"area"` (with sparkline) |
| `textMode` | `"auto"`, `"value"`, `"value_and_name"`, `"name"`, `"none"` |

### Calculation types (`calcs` values)

Used in stat, gauge, bar gauge, table reduce options, and legend calcs.

Common: `lastNotNull`, `last`, `first`, `firstNotNull`, `min`, `max`, `mean`, `sum`, `count`, `range`, `delta`, `diff`

Additional: `diffperc`, `changeCount`, `distinctCount`, `variance`, `stdDev`, `median`, `step`, `logmin`, `allIsZero`, `allIsNull`

Full list: https://grafana.com/docs/grafana/latest/panels-visualizations/query-transform-data/calculation-types/

### Gauge (`gauge`)

```json
{
  "type": "gauge",
  "options": {
    "reduceOptions": { "calcs": ["lastNotNull"] },
    "showThresholdLabels": false,
    "showThresholdMarkers": true
  },
  "fieldConfig": {
    "defaults": { "min": 0, "max": 100, "unit": "percent" }
  }
}
```

### Table (`table`)

Best with instant queries. Hide columns via overrides:

```json
{
  "type": "table",
  "fieldConfig": {
    "overrides": [{
      "matcher": { "id": "byName", "options": "Time" },
      "properties": [{ "id": "custom.hidden", "value": true }]
    }]
  }
}
```

### Text (`text`)

```json
{ "type": "text", "options": { "mode": "markdown", "content": "## Title\nContent." } }
```

---

## 4. Queries and Data Sources

### Target structure (Prometheus-compatible)

```json
"targets": [{
  "datasource": { "type": "prometheus", "uid": "datasource-uid" },
  "expr": "up{job=\"my-job\"}",
  "legendFormat": "{{instance}}",
  "refId": "A",
  "instant": false,
  "range": true,
  "interval": "",
  "editorMode": "code"
}]
```

| Field | Notes |
|-------|-------|
| `refId` | Unique per-target: `"A"`, `"B"`, etc. Referenced by transformations. |
| `legendFormat` | Template: `{{label_name}}`. Use `__auto` for automatic. |
| `interval` | Min step. Empty = auto (`$__interval`). |
| `editorMode` | `"code"` (raw query) or `"builder"` (visual). |
| `instant` / `range` | Time series panels need range; stat/gauge typically need instant. |

### Multiple queries

Add multiple targets with different `refId` values. Each renders as a separate series unless combined via transformations.

### Datasource variable

```json
"datasource": { "type": "prometheus", "uid": "$datasource" }
```

### Query gotchas

- `rate()` requires a range vector: `rate(metric[5m])`, not `rate(metric)`. **Exception:** MetricsQL auto-selects a window when omitted.
- `increase()` and `rate()` are for counters only. For gauges use `delta()` or `deriv()`.
- Always use `$__rate_interval` in `rate()`/`increase()` instead of hardcoded durations: `rate(metric[$__rate_interval])`.
- `$__rate_interval` = `max($__interval + scrape_interval, 4 * scrape_interval)`.
- Short time ranges with long scrape intervals produce gaps. `$__rate_interval` mitigates this.

---

## 5. Variables (Templating)

### Variable types

| Type | Description |
|------|-------------|
| Query | Values from datasource query |
| Custom | Static comma-separated values |
| Text box | Free-form input with optional default |
| Constant | Hidden fixed value |
| Data source | Datasource selector by type |
| Interval | Time span options with optional auto-step |
| Ad hoc filters | Key-value label filters auto-applied to all queries |
| Switch | Toggle between two values |

### Query variable

```json
{
  "name": "namespace",
  "type": "query",
  "datasource": { "type": "prometheus", "uid": "datasource-uid" },
  "query": "label_values(kube_namespace_created, namespace)",
  "refresh": 2,
  "includeAll": true,
  "allValue": ".*",
  "multi": true,
  "sort": 1,
  "regex": ""
}
```

| Field | Values |
|-------|--------|
| `refresh` | `0` = never, `1` = on dashboard load, `2` = on time range change |
| `sort` | `0` = disabled, `1` = alpha asc, `2` = alpha desc, `3` = num asc, `4` = num desc |

### Prometheus query functions

| Function | Purpose |
|----------|---------|
| `label_values(label)` | All values of a label |
| `label_values(metric, label)` | Label values for a specific metric |
| `metrics(regex)` | Metric names matching regex |
| `query_result(expr)` | Arbitrary PromQL result |
| `label_names()` | All label names |

### Variable syntax

| Syntax | Output (multi-value) | Use case |
|--------|---------------------|----------|
| `$var` | Default interpolation | `{ns=~"$var"}` |
| `${var}` | Same, avoids ambiguity | Embedded in strings |
| `${var:csv}` | `val1,val2` | Function arguments |
| `${var:pipe}` | `val1\|val2` | Pipe-separated |
| `${var:regex}` | Regex-escaped pipe-separated | Safe regex matchers |
| `${var:raw}` | No escaping | Variable is a sub-expression |
| `${var:json}` | JSON array | API payloads |
| `${var:sqlstring}` | SQL-safe single-quoted | SQL clauses |
| `${var:doublequote}` | Double-quoted, escaped | SQL strings |
| `${var:queryparam}` | `var-name=val1&...` | URL parameters |

Invalid format falls back to `glob`. Multi-value variables require `=~` regex operator. Full format list: https://grafana.com/docs/grafana/latest/dashboards/variables/variable-syntax/

### Built-in global variables

| Variable | Value |
|----------|-------|
| `$__interval` | Auto-calculated query step (e.g., `15s`, `1m`) |
| `$__interval_ms` | Same in milliseconds |
| `$__rate_interval` | `max($__interval + scrape_interval, 4 * scrape_interval)` |
| `$__range` | Dashboard time range as duration |
| `$__range_s` / `$__range_ms` | Time range in seconds / milliseconds |
| `$__from` / `$__to` | Epoch milliseconds of time range bounds |

---

## 6. Transformations

Transformations process query results client-side before rendering. Applied sequentially — order matters. Configured under `"transformations"`. All text inputs accept variable syntax.

```json
"transformations": [{
  "id": "organize",
  "options": {
    "excludeByName": { "Time": true },
    "renameByName": { "Value": "CPU %" }
  }
}]
```

### Common transformations

| ID | Purpose |
|----|---------|
| `merge` | Combine multiple query results into one table |
| `organize` | Rename, reorder, hide fields |
| `filterByValue` | Filter rows by field values |
| `calculateField` | New fields via reduce, binary/unary ops, cumulative, window functions |
| `reduce` | Collapse time series to single value per calculation |
| `groupBy` | Group rows and aggregate |
| `sortBy` | Sort by field values |
| `joinByField` | SQL-like join on a shared field |
| `convertFieldType` | Cast to numeric, string, time, boolean, enum |
| `configFromData` | Map query values to panel config (thresholds, units) |
| `extractFields` | Parse JSON, key-value, or regex from a field |
| `concatenate` | Combine all fields from all frames into one result |

Grafana has 30+ transformations. Full list: https://grafana.com/docs/grafana/latest/panels-visualizations/query-transform-data/transform-data/

### Multi-query table pattern

Combine queries A and B: `merge` transformation, then `organize` to select and rename columns.

---

## 7. Thresholds, Overrides, and Mappings

### Thresholds

```json
"fieldConfig": {
  "defaults": {
    "thresholds": {
      "mode": "absolute",
      "steps": [
        { "value": null, "color": "green" },
        { "value": 70, "color": "yellow" },
        { "value": 90, "color": "red" }
      ]
    }
  }
}
```

- `mode`: `"absolute"` (fixed values) or `"percentage"` (of min-max range).
- First step must have `"value": null` (base color).
- "Show thresholds" rendering (lines/filled regions) only works in time series, bar chart, candlestick, and trend panels.

### Field overrides

```json
"fieldConfig": {
  "overrides": [{
    "matcher": { "id": "byName", "options": "series-name" },
    "properties": [
      { "id": "color", "value": { "fixedColor": "red", "mode": "fixed" } },
      { "id": "custom.lineWidth", "value": 3 }
    ]
  }]
}
```

| Matcher ID | Targets |
|------------|---------|
| `byName` | Specific field name |
| `byRegexp` | Fields matching regex |
| `byType` | Fields by data type |
| `byFrameRefID` | All fields from a specific query (A, B, ...) |
| `byValue` | Fields matching a reducer condition |

### Value mappings

Four types: `value`, `range`, `regex`, `special`.

```json
"mappings": [
  { "type": "value", "options": { "0": { "text": "Down", "color": "red" } } },
  { "type": "value", "options": { "1": { "text": "Up", "color": "green" } } },
  { "type": "range", "options": { "from": 0, "to": 50, "result": { "text": "Low" } } },
  { "type": "regex", "options": { "pattern": ".*error.*", "result": { "text": "Error" } } },
  { "type": "special", "options": { "match": "null", "result": { "text": "N/A" } } }
]
```

Special match values: `null`, `NaN`, `true`, `false`.

---

## 8. Units and Colors

### Common unit strings

| Unit | Expects | Display |
|------|---------|---------|
| `percent` | 0-100 | `85%` |
| `percentunit` | 0-1 | `0.85` → `85%` |
| `bytes` | bytes (IEC, base-2) | `1.5 GiB` |
| `decbytes` | bytes (SI, base-10) | `1.5 GB` |
| `bits` | bits (IEC, base-2) | `12 Mib` |
| `s` | seconds | `2m 30s` |
| `ms` | milliseconds | `150 ms` |
| `short` | auto-SI suffix | `1.5K` |
| `none` | raw value | `1500` |
| `celsius` | degrees | `72 °C` |
| `reqps` | requests/sec | `1.2K req/s` |
| `ops` | operations/sec | `500 ops/s` |
| `watt` | watts | `150 W` |
| `hertz` | hertz | `3.5 GHz` |
| `dtdurationms` | duration from ms | `2h 15m` |
| `dtdurations` | duration from seconds | `1d 3h` |

Full unit list available in the Grafana UI under panel field config > Unit dropdown.

### Color specification

**Named colors:** `green`, `red`, `yellow`, `blue`, `orange`, `purple`, `white`, `transparent`. Also supports shades: `semi-dark-green`, `dark-red`, `super-light-blue`, `light-yellow`, etc.

**Hex codes:** `"#FF0000"`, `"#00FF00"`, etc.

**Color mode object** (in `fieldConfig.defaults.color`):

```json
{ "mode": "palette-classic" }
{ "mode": "palette-classic-by-name" }
{ "mode": "fixed", "fixedColor": "#FF0000" }
{ "mode": "continuous-GrYlRd" }
{ "mode": "continuous-BlYlRd" }
{ "mode": "continuous-blues" }
{ "mode": "continuous-greens" }
{ "mode": "continuous-reds" }
{ "mode": "continuous-YlRd" }
{ "mode": "shades" }
```

`palette-classic` auto-assigns colors from a fixed palette. `fixed` uses a single color. `continuous-*` creates gradient scales (useful with thresholds). `shades` varies shades of a single color.

---

## 9. Provisioning

### Dashboard provider

```yaml
# /etc/grafana/provisioning/dashboards/default.yaml
apiVersion: 1
providers:
  - name: default
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

| Field | Default | Notes |
|-------|---------|-------|
| `disableDeletion` | `false` | Prevent deletion when provisioning source is removed |
| `allowUiUpdates` | `false` | Allow saving in UI (provisioning source overwrites on next scan) |
| `updateIntervalSeconds` | `10` | Scan interval for file changes |
| `foldersFromFilesStructure` | `false` | Map directory tree to Grafana folders. Requires `folder` and `folderUid` to be unset. |

Datasource UIDs in dashboard JSON must match the UIDs of provisioned datasources (configured separately in `/etc/grafana/provisioning/datasources/`). Provisioning supports `$VAR_NAME` env var substitution.

### Exporting for provisioning

Use the API: `GET /api/dashboards/uid/<uid>`. Set `id: null` and replace hardcoded datasource UIDs with variables or provisioned names.

---

## 10. MetricsQL Differences

VictoriaMetrics implements MetricsQL, a PromQL-compatible superset. Standard PromQL queries work unchanged. Key behavioral differences that affect dashboard queries:

**Implicit lookbehind window:** `rate(metric)` is valid without `[5m]` — MetricsQL auto-selects based on query step and scrape interval.

**No extrapolation in `rate()`/`increase()`:** MetricsQL uses actual data point timestamps. Returns exact values (integers for integer counters) where PromQL would return fractional extrapolated results.

**Automatic window expansion:** If too few samples exist for `rate()`/`increase()`, MetricsQL expands the window instead of returning no data.

**Implicit `default_rollup()`:** Bare series selectors auto-wrap in `default_rollup()`. `rate(sum(metric))` becomes a subquery and likely produces wrong results. Use `sum(rate(metric[5m]))`.

**Metric name preservation:** Functions that don't change meaning (e.g., `round`, `min_over_time`) preserve the metric name. Use `keep_metric_names` modifier on others.

### Notable MetricsQL-only functions

**Label manipulation:** `label_set(q, "k", "v")`, `label_del(q, "k")`, `label_keep(q, "k")`, `label_copy(q, "src", "dst")`, `label_move(q, "src", "dst")`, `label_join(q, "dst", "sep", "src1", ...)`, `label_value(q, "label")`, `label_match(q, "label", "regex")`, `label_mismatch(q, "label", "regex")`

**Range transforms:** `range_first(q)`, `range_last(q)`, `range_avg(q)`, `range_min(q)`, `range_max(q)`, `range_quantile(phi, q)`, `range_normalize(q)`, `range_trim_outliers(k, q)`

**Gap filling:** `keep_last_value(q)`, `keep_next_value(q)`, `interpolate(q)`

**Rollup extensions:** `count_eq_over_time(q[d], N)`, `share_gt_over_time(q[d], N)`, `distinct_over_time(q[d])`, `mode_over_time(q[d])`, `mad_over_time(q[d])`, `rollup(q[d])` (returns min/max/avg as separate series)

**Other:** `union(q1, ..., qN)`, `sort_by_label(q, "label")`, `limit_offset(limit, offset, q)`, `running_avg(q)`, `running_sum(q)`, `smooth_exponential(q, sf)`, `remove_resets(q)`

Full reference: https://docs.victoriametrics.com/victoriametrics/metricsql/

---

## 11. Documentation Links

### Grafana

| Topic | URL |
|-------|-----|
| Dashboard JSON model | https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/ |
| Dashboard JSON schema v2 | https://grafana.com/docs/grafana/latest/as-code/observability-as-code/schema-v2/ |
| Visualizations overview | https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/ |
| Time series panel | https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/time-series/ |
| Stat panel | https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/stat/ |
| Gauge panel | https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/gauge/ |
| Table panel | https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/table/ |
| Bar gauge panel | https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/bar-gauge/ |
| Calculation types | https://grafana.com/docs/grafana/latest/panels-visualizations/query-transform-data/calculation-types/ |
| Variables | https://grafana.com/docs/grafana/latest/dashboards/variables/ |
| Add variables | https://grafana.com/docs/grafana/latest/dashboards/variables/add-template-variables/ |
| Variable syntax | https://grafana.com/docs/grafana/latest/dashboards/variables/variable-syntax/ |
| Prometheus variables | https://grafana.com/docs/grafana/latest/datasources/prometheus/template-variables/ |
| Transformations | https://grafana.com/docs/grafana/latest/panels-visualizations/query-transform-data/transform-data/ |
| Thresholds | https://grafana.com/docs/grafana/latest/panels-visualizations/configure-thresholds/ |
| Value mappings | https://grafana.com/docs/grafana/latest/panels-visualizations/configure-value-mappings/ |
| Field overrides | https://grafana.com/docs/grafana/latest/panels-visualizations/configure-overrides/ |
| Provisioning | https://grafana.com/docs/grafana/latest/administration/provisioning/ |
| HTTP API | https://grafana.com/docs/grafana/latest/developers/http_api/ |
| Dashboard API | https://grafana.com/docs/grafana/latest/developers/http_api/dashboard/ |

### PromQL / MetricsQL

| Topic | URL |
|-------|-----|
| PromQL basics | https://prometheus.io/docs/prometheus/latest/querying/basics/ |
| PromQL functions | https://prometheus.io/docs/prometheus/latest/querying/functions/ |
| PromQL operators | https://prometheus.io/docs/prometheus/latest/querying/operators/ |
| MetricsQL reference | https://docs.victoriametrics.com/victoriametrics/metricsql/ |

### Community

| Topic | URL |
|-------|-----|
| Community dashboards | https://grafana.com/grafana/dashboards/ |
| Plugin catalog | https://grafana.com/grafana/plugins/ |
| Grafana Play (live examples) | https://play.grafana.org/ |
