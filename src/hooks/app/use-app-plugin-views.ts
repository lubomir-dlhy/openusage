import { useEffect, useMemo } from "react"
import type { ActiveView, NavPlugin } from "@/components/side-nav"
import type { PluginMeta } from "@/lib/plugin-types"
import type { PluginSettings } from "@/lib/settings"
import type { PluginState } from "@/hooks/app/types"

export type DisplayPluginState = {
  meta: PluginMeta
  instanceId: string
  label: string | null
  /** Per-account custom icon (data/image URL); overrides the provider icon in-app. */
  customIconUrl?: string
} & PluginState

const EMPTY_STATE: PluginState = {
  data: null,
  loading: false,
  error: null,
  lastManualRefreshAt: null,
  lastUpdatedAt: null,
}

type UseAppPluginViewsArgs = {
  activeView: ActiveView
  setActiveView: (view: ActiveView) => void
  pluginSettings: PluginSettings | null
  pluginsMeta: PluginMeta[]
  pluginStates: Record<string, PluginState>
}

export function useAppPluginViews({
  activeView,
  setActiveView,
  pluginSettings,
  pluginsMeta,
  pluginStates,
}: UseAppPluginViewsArgs) {
  const displayPlugins = useMemo<DisplayPluginState[]>(() => {
    if (!pluginSettings) return []
    const disabledSet = new Set(pluginSettings.disabled)
    const metaById = new Map(pluginsMeta.map((plugin) => [plugin.id, plugin]))
    const instById = new Map(
      (pluginSettings.instances ?? []).map((inst) => [inst.instanceId, inst])
    )

    return pluginSettings.order
      .filter((id) => !disabledSet.has(id))
      .map((instanceId): DisplayPluginState | null => {
        const inst = instById.get(instanceId)
        const providerId = inst?.providerId ?? instanceId
        const meta = metaById.get(providerId)
        if (!meta) return null
        const state = pluginStates[instanceId] ?? EMPTY_STATE
        return {
          meta,
          instanceId,
          label: inst?.label ?? null,
          customIconUrl: inst?.icon ?? undefined,
          ...state,
        }
      })
      .filter((plugin): plugin is DisplayPluginState => Boolean(plugin))
  }, [pluginSettings, pluginStates, pluginsMeta])

  const navPlugins = useMemo<NavPlugin[]>(() => {
    return displayPlugins.map((plugin) => ({
      id: plugin.instanceId,
      name: plugin.label ? `${plugin.meta.name} · ${plugin.label}` : plugin.meta.name,
      iconUrl: plugin.meta.iconUrl,
      brandColor: plugin.meta.brandColor,
      customIconUrl: plugin.customIconUrl,
    }))
  }, [displayPlugins])

  useEffect(() => {
    if (activeView === "home" || activeView === "settings") return
    if (!pluginSettings) return
    const isKnownInstance =
      (pluginSettings.instances ?? []).some(
        (inst) => inst.instanceId === activeView
      ) || pluginSettings.order.includes(activeView)
    if (!isKnownInstance) return
    const isStillEnabled = navPlugins.some((plugin) => plugin.id === activeView)
    if (!isStillEnabled) {
      setActiveView("home")
    }
  }, [activeView, navPlugins, pluginSettings, setActiveView])

  const selectedPlugin = useMemo(() => {
    if (activeView === "home" || activeView === "settings") return null
    return displayPlugins.find((plugin) => plugin.instanceId === activeView) ?? null
  }, [activeView, displayPlugins])

  return {
    displayPlugins,
    navPlugins,
    selectedPlugin,
  }
}
