export type ProgressFormat =
  | { kind: "percent" }
  | { kind: "dollars" }
  | { kind: "count"; suffix: string }

export type BarChartPoint = {
  label: string
  value: number
  valueLabel?: string
}

export type MetricLine =
  | { type: "text"; label: string; value: string; color?: string; subtitle?: string }
  | {
      type: "progress"
      label: string
      used: number
      limit: number
      format: ProgressFormat
      resetsAt?: string
      periodDurationMs?: number
      color?: string
    }
  | { type: "badge"; label: string; text: string; color?: string; subtitle?: string }
  | { type: "barChart"; label: string; points: BarChartPoint[]; note?: string; color?: string }

export type ManifestLine = {
  type: "text" | "progress" | "badge" | "barChart"
  label: string
  scope: "overview" | "detail"
}

export type PluginLink = {
  label: string
  url: string
}

export type PluginOutput = {
  providerId: string
  /**
   * Unique id of the account instance this output belongs to. Equals
   * `providerId` for the default account; distinct for extra accounts of the
   * same provider (e.g. "claude#2").
   */
  instanceId: string
  /** User-facing account label (e.g. "Work"); null for the default account. */
  label?: string | null
  displayName: string
  plan?: string
  lines: MetricLine[]
  iconUrl: string
}

export type PluginMeta = {
  id: string
  name: string
  iconUrl: string
  brandColor?: string
  lines: ManifestLine[]
  links?: PluginLink[]
  /** Ordered list of primary metric candidates. Frontend picks first available. */
  primaryCandidates: string[]
  /** Label of the line marked `"period": "weekly"`, if the provider has one. */
  weeklyCandidate?: string
}

export type PluginDisplayState = {
  meta: PluginMeta
  /** Account instance id (equals meta.id for the default account). */
  instanceId: string
  /** Account label (e.g. "Work"); null for the default account. */
  label: string | null
  data: PluginOutput | null
  loading: boolean
  error: string | null
  lastManualRefreshAt: number | null
  lastUpdatedAt: number | null
}
