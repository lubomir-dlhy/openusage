import type { PluginMeta, PluginOutput } from "@/lib/plugin-types"
import type { PluginSettings } from "@/lib/settings"
import { DEFAULT_DISPLAY_MODE, type DisplayMode } from "@/lib/settings"
import { clamp01 } from "@/lib/utils"

type PluginState = {
  data: PluginOutput | null
  loading: boolean
  error: string | null
}

export type TrayPrimaryBar = {
  /** instanceId of the account (equals providerId for the default account). */
  id: string
  /** providerId of the plugin, for meta lookup when `id` is a non-default instanceId. */
  providerId?: string
  /** User label for a non-default account instance (e.g. "Work"); undefined for the default. */
  accountLabel?: string
  fraction?: number
  /** Label of the metric line that produced this bar (when data is available). */
  label?: string
  /** True when the value came from the provider's declared weekly line. */
  weekly?: boolean
}

type ProgressLine = Extract<
  PluginOutput["lines"][number],
  { type: "progress"; label: string; used: number; limit: number }
>

function isProgressLine(line: PluginOutput["lines"][number]): line is ProgressLine {
  return line.type === "progress"
}

export function getTrayPrimaryBars(args: {
  pluginsMeta: PluginMeta[]
  pluginSettings: PluginSettings | null
  pluginStates: Record<string, PluginState | undefined>
  maxBars?: number
  displayMode?: DisplayMode
  pluginId?: string
  preferWeekly?: boolean
}): TrayPrimaryBar[] {
  const {
    pluginsMeta,
    pluginSettings,
    pluginStates,
    maxBars = 4,
    displayMode = DEFAULT_DISPLAY_MODE,
    pluginId,
    preferWeekly = false,
  } = args
  if (!pluginSettings) return []

  const metaById = new Map(pluginsMeta.map((p) => [p.id, p]))
  const instById = new Map(
    (pluginSettings.instances ?? []).map((inst) => [inst.instanceId, inst])
  )
  const disabled = new Set(pluginSettings.disabled)
  const orderedIds = pluginId
    ? [pluginId]
    : pluginSettings.order

  const out: TrayPrimaryBar[] = []
  for (const id of orderedIds) {
    if (disabled.has(id)) continue
    // `id` is an instanceId; resolve to its providerId to find the plugin meta
    // (icon, primaryCandidates). Falls back to `id` for default instances.
    const inst = instById.get(id)
    const providerId = inst?.providerId ?? id
    const meta = metaById.get(providerId)
    if (!meta) continue
    
    // Skip plugins with no primary metric. Weekly mode is an override of the
    // primary (see preferWeekly below), not a standalone mode — so a provider
    // must define primaryCandidates to appear in the menubar; a weekly-only
    // provider is intentionally skipped.
    if (!meta.primaryCandidates || meta.primaryCandidates.length === 0) continue

    const state = pluginStates[id]
    const data = state?.data ?? null

    let fraction: number | undefined
    let label: string | undefined
    let weekly: true | undefined
    if (data) {
      // Prefer the declared weekly line when requested and present in data.
      const weeklyLabel = preferWeekly ? meta.weeklyCandidate : undefined
      const usesWeekly =
        weeklyLabel !== undefined &&
        data.lines.some((line) => isProgressLine(line) && line.label === weeklyLabel)

      // Otherwise fall back to the first primary candidate that exists in data.
      const metricLabel = usesWeekly
        ? weeklyLabel
        : meta.primaryCandidates.find((candidate) =>
            data.lines.some((line) => isProgressLine(line) && line.label === candidate)
          )

      if (metricLabel) {
        label = metricLabel
        weekly = usesWeekly || undefined
        const metricLine = data.lines.find(
          (line): line is ProgressLine =>
            isProgressLine(line) && line.label === metricLabel
        )
        if (metricLine && metricLine.limit > 0) {
          const shownAmount =
            displayMode === "used"
              ? metricLine.used
              : metricLine.limit - metricLine.used
          fraction = clamp01(shownAmount / metricLine.limit)
        }
      }
    }

    const bar: TrayPrimaryBar = { id, fraction, label, weekly }
    // Only annotate non-default instances so default-account bars stay identical.
    if (providerId !== id) bar.providerId = providerId
    if (inst?.label) bar.accountLabel = inst.label
    out.push(bar)
    if (out.length >= maxBars) break
  }

  return out
}

