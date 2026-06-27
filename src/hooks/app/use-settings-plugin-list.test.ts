import { renderHook } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { useSettingsPluginList } from "@/hooks/app/use-settings-plugin-list"
import type { PluginMeta } from "@/lib/plugin-types"
import type { PluginSettings } from "@/lib/settings"

function createPluginMeta(id: string, name: string): PluginMeta {
  return {
    id,
    name,
    iconUrl: `/${id}.svg`,
    brandColor: "#000000",
    lines: [],
    primaryCandidates: [],
  }
}

describe("useSettingsPluginList", () => {
  it("returns ordered settings plugins with enabled state", () => {
    const pluginSettings: PluginSettings = {
      order: ["codex", "missing", "cursor"],
      disabled: ["cursor"],
      instances: [],
    }

    const { result } = renderHook(() =>
      useSettingsPluginList({
        pluginSettings,
        pluginsMeta: [
          createPluginMeta("cursor", "Cursor"),
          createPluginMeta("codex", "Codex"),
        ],
      })
    )

    expect(result.current).toEqual([
      { id: "codex", providerId: "codex", name: "Codex", label: null, isDefault: true, enabled: true, env: undefined, icon: null },
      { id: "cursor", providerId: "cursor", name: "Cursor", label: null, isDefault: true, enabled: false, env: undefined, icon: null },
    ])
  })

  it("returns empty list when settings are not loaded", () => {
    const { result } = renderHook(() =>
      useSettingsPluginList({
        pluginSettings: null,
        pluginsMeta: [createPluginMeta("codex", "Codex")],
      })
    )

    expect(result.current).toEqual([])
  })
})
