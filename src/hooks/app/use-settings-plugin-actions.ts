import { useCallback } from "react"
import {
  addInstance,
  editInstance,
  removeInstance,
  resolveProbeInstances,
  savePluginSettings,
  PROVIDER_CONFIG_DIR_ENV,
  type PluginSettings,
  type ProbeInstance,
} from "@/lib/settings"

const TRAY_SETTINGS_DEBOUNCE_MS = 2000

type ScheduleTrayIconUpdate = (reason: "probe" | "settings" | "init", delayMs?: number) => void

type UseSettingsPluginActionsArgs = {
  pluginSettings: PluginSettings | null
  setPluginSettings: (value: PluginSettings | null) => void
  setLoadingForPlugins: (ids: string[]) => void
  setErrorForPlugins: (ids: string[], error: string) => void
  startBatch: (instances?: ProbeInstance[]) => Promise<string[] | undefined>
  scheduleTrayIconUpdate: ScheduleTrayIconUpdate
}

export function useSettingsPluginActions({
  pluginSettings,
  setPluginSettings,
  setLoadingForPlugins,
  setErrorForPlugins,
  startBatch,
  scheduleTrayIconUpdate,
}: UseSettingsPluginActionsArgs) {
  const handleReorder = useCallback((orderedIds: string[]) => {
    if (!pluginSettings) return
    // orderedIds may be a subset (e.g. nav-only, excluding disabled plugins).
    // Re-insert any missing IDs from the previous order at their original
    // relative positions so disabled plugins are not dropped.
    const orderedSet = new Set(orderedIds)
    const missing = (pluginSettings.order ?? []).filter((id) => !orderedSet.has(id))
    const merged = [...orderedIds]
    for (const id of missing) {
      const prevIdx = (pluginSettings.order ?? []).indexOf(id)
      // Insert after the last merged entry whose original index < prevIdx
      let insertAt = 0 // default: prepend if id originally preceded all visible entries
      for (let i = merged.length - 1; i >= 0; i--) {
        const mergedPrevIdx = (pluginSettings.order ?? []).indexOf(merged[i])
        if (mergedPrevIdx < prevIdx) {
          insertAt = i + 1
          break
        }
      }
      merged.splice(insertAt, 0, id)
    }
    const nextSettings: PluginSettings = {
      ...pluginSettings,
      order: merged,
    }
    setPluginSettings(nextSettings)
    scheduleTrayIconUpdate("settings", TRAY_SETTINGS_DEBOUNCE_MS)
    void savePluginSettings(nextSettings).catch((error) => {
      console.error("Failed to save plugin order:", error)
    })
  }, [pluginSettings, scheduleTrayIconUpdate, setPluginSettings])

  const handleToggle = useCallback((id: string) => {
    if (!pluginSettings) return
    const wasDisabled = pluginSettings.disabled.includes(id)
    const disabled = new Set(pluginSettings.disabled)

    if (wasDisabled) {
      disabled.delete(id)
      setLoadingForPlugins([id])
      startBatch(resolveProbeInstances(pluginSettings, [id])).catch((error) => {
        console.error("Failed to start probe for enabled plugin:", error)
        setErrorForPlugins([id], "Failed to start probe")
      })
    } else {
      disabled.add(id)
    }

    const nextSettings: PluginSettings = {
      ...pluginSettings,
      disabled: Array.from(disabled),
    }
    setPluginSettings(nextSettings)
    scheduleTrayIconUpdate("settings", TRAY_SETTINGS_DEBOUNCE_MS)
    void savePluginSettings(nextSettings).catch((error) => {
      console.error("Failed to save plugin toggle:", error)
    })
  }, [
    pluginSettings,
    scheduleTrayIconUpdate,
    setErrorForPlugins,
    setLoadingForPlugins,
    setPluginSettings,
    startBatch,
  ])

  const handleAddInstance = useCallback(
    (providerId: string, label: string, configDir: string, icon?: string | null) => {
      if (!pluginSettings) return
      const trimmedDir = configDir.trim()
      const envVar = PROVIDER_CONFIG_DIR_ENV[providerId]
      const env =
        envVar && trimmedDir ? { [envVar]: trimmedDir } : undefined

      const nextSettings = addInstance(pluginSettings, providerId, label, env, icon ?? null)
      setPluginSettings(nextSettings)
      scheduleTrayIconUpdate("settings", TRAY_SETTINGS_DEBOUNCE_MS)
      void savePluginSettings(nextSettings).catch((error) => {
        console.error("Failed to save new account:", error)
      })

      // Probe the freshly added account so its card populates immediately.
      const added = nextSettings.instances[nextSettings.instances.length - 1]
      if (added) {
        setLoadingForPlugins([added.instanceId])
        startBatch(resolveProbeInstances(nextSettings, [added.instanceId])).catch(
          (error) => {
            console.error("Failed to start probe for new account:", error)
            setErrorForPlugins([added.instanceId], "Failed to start probe")
          }
        )
      }
    },
    [
      pluginSettings,
      scheduleTrayIconUpdate,
      setErrorForPlugins,
      setLoadingForPlugins,
      setPluginSettings,
      startBatch,
    ]
  )

  const handleEditInstance = useCallback(
    (
      instanceId: string,
      patch: { label: string; configDir: string; icon?: string | null }
    ) => {
      if (!pluginSettings) return
      const inst = pluginSettings.instances.find((i) => i.instanceId === instanceId)
      if (!inst) return
      const trimmedDir = patch.configDir.trim()
      const envVar = PROVIDER_CONFIG_DIR_ENV[inst.providerId]
      const env =
        envVar && trimmedDir ? { [envVar]: trimmedDir } : undefined

      const nextSettings = editInstance(pluginSettings, instanceId, {
        label: patch.label,
        env,
        icon: patch.icon ?? null,
      })
      if (nextSettings === pluginSettings) return
      setPluginSettings(nextSettings)
      scheduleTrayIconUpdate("settings", TRAY_SETTINGS_DEBOUNCE_MS)
      void savePluginSettings(nextSettings).catch((error) => {
        console.error("Failed to save edited account:", error)
      })

      // Re-probe: the config dir (data source) may have changed.
      setLoadingForPlugins([instanceId])
      startBatch(resolveProbeInstances(nextSettings, [instanceId])).catch((error) => {
        console.error("Failed to start probe for edited account:", error)
        setErrorForPlugins([instanceId], "Failed to start probe")
      })
    },
    [
      pluginSettings,
      scheduleTrayIconUpdate,
      setErrorForPlugins,
      setLoadingForPlugins,
      setPluginSettings,
      startBatch,
    ]
  )

  const handleRemoveInstance = useCallback(
    (instanceId: string) => {
      if (!pluginSettings) return
      const nextSettings = removeInstance(pluginSettings, instanceId)
      if (nextSettings === pluginSettings) return // default account / no-op
      setPluginSettings(nextSettings)
      scheduleTrayIconUpdate("settings", TRAY_SETTINGS_DEBOUNCE_MS)
      void savePluginSettings(nextSettings).catch((error) => {
        console.error("Failed to remove account:", error)
      })
    },
    [pluginSettings, scheduleTrayIconUpdate, setPluginSettings]
  )

  return {
    handleReorder,
    handleToggle,
    handleAddInstance,
    handleEditInstance,
    handleRemoveInstance,
  }
}
