import { useMemo } from "react"
import type { PluginMeta } from "@/lib/plugin-types"
import type { PluginSettings } from "@/lib/settings"

export type SettingsPluginState = {
  /** instanceId (equals providerId for the default account). Used as row key. */
  id: string
  providerId: string
  name: string
  /** Account label for extra accounts; null for the default account. */
  label: string | null
  /** True when this is the provider's default account (not user-added). */
  isDefault: boolean
  enabled: boolean
  /** Env override (config-dir) for extra accounts — used to prefill the edit form. */
  env?: Record<string, string>
  /** Per-account custom icon (data/image URL); used to prefill the edit form. */
  icon?: string | null
}

type UseSettingsPluginListArgs = {
  pluginSettings: PluginSettings | null
  pluginsMeta: PluginMeta[]
}

export function useSettingsPluginList({ pluginSettings, pluginsMeta }: UseSettingsPluginListArgs) {
  return useMemo<SettingsPluginState[]>(() => {
    if (!pluginSettings) return []
    const pluginMap = new Map(pluginsMeta.map((plugin) => [plugin.id, plugin]))
    const instById = new Map(
      (pluginSettings.instances ?? []).map((inst) => [inst.instanceId, inst])
    )

    return pluginSettings.order
      .map((id): SettingsPluginState | null => {
        const inst = instById.get(id)
        const providerId = inst?.providerId ?? id
        const meta = pluginMap.get(providerId)
        if (!meta) return null
        return {
          id,
          providerId,
          name: meta.name,
          label: inst?.label ?? null,
          isDefault: providerId === id,
          enabled: !pluginSettings.disabled.includes(id),
          env: inst?.env,
          icon: inst?.icon ?? null,
        }
      })
      .filter((plugin): plugin is SettingsPluginState => Boolean(plugin))
  }, [pluginSettings, pluginsMeta])
}
