import { ProviderCard } from "@/components/provider-card"
import type { DisplayPluginState } from "@/hooks/app/use-app-plugin-views"
import type { DisplayMode, ResetTimerDisplayMode, TimeFormatMode } from "@/lib/settings"

interface OverviewPageProps {
  plugins: DisplayPluginState[]
  onRetryPlugin?: (pluginId: string) => void
  displayMode: DisplayMode
  resetTimerDisplayMode: ResetTimerDisplayMode
  timeFormatMode?: TimeFormatMode
  onResetTimerDisplayModeToggle?: () => void
}

export function OverviewPage({
  plugins,
  onRetryPlugin,
  displayMode,
  resetTimerDisplayMode,
  timeFormatMode = "auto",
  onResetTimerDisplayModeToggle,
}: OverviewPageProps) {
  return (
    <div>
      {plugins.length === 0 ? (
        <div className="text-center text-muted-foreground py-8">
          No providers enabled
        </div>
      ) : (
        plugins.map((plugin, index) => (
          <ProviderCard
            key={plugin.instanceId}
            name={plugin.meta.name}
            label={plugin.label}
            customIconUrl={plugin.customIconUrl}
            plan={plugin.data?.plan}
            showSeparator={index < plugins.length - 1}
            loading={plugin.loading}
            error={plugin.error}
            lines={plugin.data?.lines ?? []}
            skeletonLines={plugin.meta.lines}
            lastManualRefreshAt={plugin.lastManualRefreshAt}
            lastUpdatedAt={plugin.lastUpdatedAt}
            onRetry={onRetryPlugin ? () => onRetryPlugin(plugin.instanceId) : undefined}
            scopeFilter="overview"
            displayMode={displayMode}
            resetTimerDisplayMode={resetTimerDisplayMode}
            timeFormatMode={timeFormatMode}
            onResetTimerDisplayModeToggle={onResetTimerDisplayModeToggle}
          />
        ))
      )}
    </div>
  )
}
