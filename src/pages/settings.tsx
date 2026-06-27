import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  arrayMove,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { Fragment, useMemo, useRef, useState } from "react";
import { GripVertical, Pencil, Plus, Trash2 } from "lucide-react";
import { Checkbox } from "@/components/ui/checkbox";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ACCOUNT_ICON_PRESETS } from "@/lib/account-icon-presets";
import { open as openFolderDialog } from "@tauri-apps/plugin-dialog";
import { invoke } from "@tauri-apps/api/core";
import { GlobalShortcutSection } from "@/components/global-shortcut-section";
import { getBarFillLayout, getTrayIconSizePx } from "@/lib/tray-bars-icon";
import {
  AUTO_UPDATE_OPTIONS,
  DISPLAY_MODE_OPTIONS,
  MENUBAR_ICON_STYLE_OPTIONS,
  MENUBAR_METRIC_OPTIONS,
  RESET_TIMER_DISPLAY_OPTIONS,
  THEME_OPTIONS,
  TIME_FORMAT_OPTIONS,
  type AutoUpdateIntervalMinutes,
  type DisplayMode,
  type GlobalShortcut,
  type MenubarIconStyle,
  type MenubarMetric,
  type ResetTimerDisplayMode,
  type ThemeMode,
  type TimeFormatMode,
} from "@/lib/settings";
import { getTimeFormatter } from "@/lib/reset-tooltip";
import type { TraySettingsPreview } from "@/hooks/app/use-tray-icon";
import { cn } from "@/lib/utils";

interface PluginConfig {
  id: string;
  providerId: string;
  name: string;
  label: string | null;
  isDefault: boolean;
  enabled: boolean;
  env?: Record<string, string>;
  icon?: string | null;
}

interface AddableProvider {
  id: string;
  name: string;
}

// Providers whose multi-account config-dir env var is known (others are hidden
// from the "Add account" picker since we can't point them at a second login).
const MULTI_ACCOUNT_PROVIDERS = new Set(["claude", "codex"]);

const TRAY_PREVIEW_SIZE_PX = getTrayIconSizePx(1);

const PREVIEW_BAR_TRACK_PX = 20;

function getPreviewBarLayout(fraction: number): { fillPercent: number; remainderPercent: number } {
  const { fillW, remainderDrawW } = getBarFillLayout(PREVIEW_BAR_TRACK_PX, fraction);
  return {
    fillPercent: (fillW / PREVIEW_BAR_TRACK_PX) * 100,
    remainderPercent: (remainderDrawW / PREVIEW_BAR_TRACK_PX) * 100,
  };
}

function ProviderIconMask({
  iconUrl,
  isActive,
  sizePx,
}: {
  iconUrl?: string;
  isActive: boolean;
  sizePx: number;
}) {
  const colorClass = isActive ? "bg-primary-foreground" : "bg-foreground";
  if (iconUrl) {
    return (
      <div
        aria-hidden
        className={cn("shrink-0", colorClass)}
        style={{
          width: `${sizePx}px`,
          height: `${sizePx}px`,
          WebkitMaskImage: `url(${iconUrl})`,
          WebkitMaskSize: "contain",
          WebkitMaskRepeat: "no-repeat",
          WebkitMaskPosition: "center",
          maskImage: `url(${iconUrl})`,
          maskSize: "contain",
          maskRepeat: "no-repeat",
          maskPosition: "center",
        }}
      />
    );
  }
  const textClass = isActive ? "text-primary-foreground" : "text-foreground";
  return (
    <svg aria-hidden viewBox="0 0 26 26" className={cn("shrink-0", textClass)} style={{ width: `${sizePx}px`, height: `${sizePx}px` }}>
      <circle cx="13" cy="13" r="9" fill="none" stroke="currentColor" strokeWidth="3.5" opacity={0.3} />
    </svg>
  );
}

function MenubarIconStylePreview({
  style,
  isActive,
  traySettingsPreview,
}: {
  style: MenubarIconStyle;
  isActive: boolean;
  traySettingsPreview: TraySettingsPreview;
}) {
  const textClass = isActive ? "text-primary-foreground" : "text-foreground";

  if (style === "provider") {
    return (
      <div className="inline-flex items-center gap-0.5">
        <ProviderIconMask
          iconUrl={traySettingsPreview.providerIconUrl}
          isActive={isActive}
          sizePx={TRAY_PREVIEW_SIZE_PX}
        />
        <span className={cn("text-[12px] font-semibold tabular-nums leading-none", textClass)}>
          {traySettingsPreview.providerPercentText}
        </span>
      </div>
    );
  }

  if (style === "bars") {
    const trackClass = isActive ? "bg-primary-foreground/15" : "bg-foreground/15";
    const remainderClass = isActive ? "bg-primary-foreground/20" : "bg-foreground/15";
    const fillClass = isActive ? "bg-primary-foreground" : "bg-foreground";
    const fractions = traySettingsPreview.bars.length > 0
      ? traySettingsPreview.bars.map((b) => b.fraction ?? 0)
      : [0.83, 0.7, 0.56];

    return (
      <div className="flex items-center">
        <div className="flex flex-col gap-0.5 w-5">
          {fractions.map((fraction, i) => {
            const { fillPercent, remainderPercent } = getPreviewBarLayout(fraction);
            return (
              <div key={i} className={cn("relative h-1 rounded-sm", trackClass)}>
                {remainderPercent > 0 && (
                  <span
                    aria-hidden
                    className={remainderClass}
                    style={{
                      position: "absolute",
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: `${remainderPercent}%`,
                      borderRadius: "1px 2px 2px 1px",
                    }}
                  />
                )}
                <div
                  className={cn("h-1", fillClass)}
                  style={{ width: `${fillPercent}%`, borderRadius: "2px 1px 1px 2px" }}
                />
              </div>
            );
          })}
        </div>
      </div>
    );
  }

  if (style === "donut") {
    const fraction = traySettingsPreview.providerBars[0]?.fraction ?? 0;
    const clamped = Math.max(0, Math.min(1, fraction));
    return (
      <div className="inline-flex items-center gap-1">
        <ProviderIconMask
          iconUrl={traySettingsPreview.providerIconUrl}
          isActive={isActive}
          sizePx={TRAY_PREVIEW_SIZE_PX}
        />
        <svg aria-hidden viewBox="0 0 26 26" className={cn("shrink-0", textClass)} style={{ width: `${TRAY_PREVIEW_SIZE_PX}px`, height: `${TRAY_PREVIEW_SIZE_PX}px` }}>
          <circle
            cx="13" cy="13" r="9"
            fill="none" stroke="currentColor" strokeWidth="4"
            opacity={isActive ? 0.2 : 0.15}
          />
          {clamped > 0 && (
            <circle
              cx="13" cy="13" r="9"
              fill="none" stroke="currentColor" strokeWidth="4"
              strokeLinecap="butt"
              pathLength="100"
              strokeDasharray={`${Math.round(clamped * 100)} 100`}
              transform="rotate(-90 13 13)"
            />
          )}
        </svg>
      </div>
    );
  }

  return null;
}

function SortablePluginItem({
  plugin,
  onToggle,
  onRemove,
  onEdit,
}: {
  plugin: PluginConfig;
  onToggle: (id: string) => void;
  onRemove: (instanceId: string) => void;
  onEdit: (instanceId: string) => void;
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: plugin.id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      onClick={() => onToggle(plugin.id)}
      className={cn(
        "flex items-center gap-3 px-3 py-2 rounded-md bg-card cursor-pointer",
        "border border-transparent",
        isDragging && "opacity-50 border-border"
      )}
    >
      <button
        type="button"
        onClick={(e) => e.stopPropagation()}
        className="touch-none cursor-grab active:cursor-grabbing text-muted-foreground hover:text-foreground transition-colors"
        {...attributes}
        {...listeners}
      >
        <GripVertical className="h-4 w-4" />
      </button>

      <span
        className={cn(
          "flex-1 min-w-0 truncate text-sm",
          !plugin.enabled && "text-muted-foreground"
        )}
      >
        {plugin.name}
        {plugin.label ? (
          <span className="ml-1.5 text-xs text-muted-foreground">
            {plugin.label}
          </span>
        ) : null}
      </span>

      {!plugin.isDefault && plugin.icon && (
        <img
          src={plugin.icon}
          alt=""
          aria-hidden
          className="size-5 rounded object-contain shrink-0 bg-[#F0EEE6] p-px"
          draggable={false}
        />
      )}

      {!plugin.isDefault && (
        <button
          type="button"
          aria-label="Edit account"
          onClick={(e) => {
            e.stopPropagation();
            onEdit(plugin.id);
          }}
          className="text-muted-foreground hover:text-foreground transition-colors"
        >
          <Pencil className="h-4 w-4" />
        </button>
      )}

      {!plugin.isDefault && (
        <button
          type="button"
          aria-label="Remove account"
          onClick={(e) => {
            e.stopPropagation();
            onRemove(plugin.id);
          }}
          className="text-muted-foreground hover:text-destructive transition-colors"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      )}

      {/* Wrap to stop Base UI's internal input.click() from bubbling to the row div */}
      <span onClick={(e) => e.stopPropagation()}>
        <Checkbox
          key={`${plugin.id}-${plugin.enabled}`}
          checked={plugin.enabled}
          onCheckedChange={() => onToggle(plugin.id)}
        />
      </span>
    </div>
  );
}

function IconPicker({
  value,
  onChange,
}: {
  value: string | null;
  onChange: (value: string | null) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);

  const handleFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") onChange(reader.result);
    };
    reader.readAsDataURL(file);
    e.target.value = "";
  };

  return (
    <div className="space-y-1.5">
      <span className="text-xs text-muted-foreground">Icon</span>
      <div className="flex items-center gap-2 flex-wrap">
        <div
          aria-label="Icon preview"
          className="size-9 rounded-md border bg-background flex items-center justify-center overflow-hidden shrink-0"
        >
          {value ? (
            <img src={value} alt="" className="size-full object-contain" />
          ) : (
            <span className="text-[9px] text-muted-foreground">Default</span>
          )}
        </div>
        {ACCOUNT_ICON_PRESETS.map((preset) => (
          <button
            key={preset.id}
            type="button"
            title={preset.label}
            aria-label={preset.label}
            onClick={() => onChange(preset.dataUrl)}
            className={cn(
              "size-9 rounded-md border bg-background overflow-hidden transition-shadow",
              value === preset.dataUrl ? "ring-2 ring-primary" : "hover:border-foreground/30"
            )}
          >
            <img src={preset.dataUrl} alt={preset.label} className="size-full object-contain" />
          </button>
        ))}
        <Button type="button" variant="outline" size="sm" onClick={() => fileRef.current?.click()}>
          Upload
        </Button>
        {value ? (
          <Button type="button" variant="ghost" size="sm" onClick={() => onChange(null)}>
            Default
          </Button>
        ) : null}
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={handleFile}
        />
      </div>
    </div>
  );
}

function AccountForm({
  mode,
  providers,
  initial,
  onSubmit,
  onCancel,
}: {
  mode: "add" | "edit";
  providers: AddableProvider[];
  initial?: {
    providerId: string;
    providerName?: string;
    label: string;
    configDir: string;
    icon: string | null;
  };
  onSubmit: (
    providerId: string,
    label: string,
    configDir: string,
    icon: string | null
  ) => void;
  onCancel: () => void;
}) {
  const addable = useMemo(
    () => providers.filter((p) => MULTI_ACCOUNT_PROVIDERS.has(p.id)),
    [providers]
  );
  const [providerId, setProviderId] = useState(
    initial?.providerId ?? addable[0]?.id ?? ""
  );
  const [label, setLabel] = useState(initial?.label ?? "");
  const [configDir, setConfigDir] = useState(initial?.configDir ?? "");
  const [icon, setIcon] = useState<string | null>(initial?.icon ?? null);

  const canSubmit = Boolean(providerId && label.trim() && configDir.trim());
  const configEnvName = providerId === "codex" ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR";

  const chooseFolder = async () => {
    // Keep the menu-bar panel from auto-hiding while the native dialog has focus.
    try {
      await invoke("set_dialog_guard", { active: true });
    } catch {
      // non-tauri / command missing — proceed anyway
    }
    try {
      const dir = await openFolderDialog({
        directory: true,
        multiple: false,
        title: "Select config folder",
        defaultPath: configDir || undefined,
      });
      if (typeof dir === "string") setConfigDir(dir);
    } catch (e) {
      console.error("Folder picker failed:", e);
    } finally {
      try {
        await invoke("set_dialog_guard", { active: false });
      } catch {
        // ignore
      }
    }
  };

  return (
    <div className="mt-1 rounded-md bg-card p-3 space-y-3 min-w-0">
      <div className="space-y-1 min-w-0">
        <span className="text-xs text-muted-foreground">Provider</span>
        {mode === "add" ? (
          <select
            aria-label="Provider"
            value={providerId}
            onChange={(e) => setProviderId(e.target.value)}
            className="w-full h-8 rounded-md border bg-background px-2 text-sm"
          >
            {addable.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        ) : (
          <div className="w-full h-8 rounded-md border bg-muted px-2 text-sm flex items-center text-muted-foreground truncate">
            {initial?.providerName ?? providerId}
          </div>
        )}
      </div>

      <div className="space-y-1 min-w-0">
        <span className="text-xs text-muted-foreground">Label</span>
        <input
          aria-label="Account label"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="e.g. Work"
          className="w-full h-8 rounded-md border bg-background px-2 text-sm"
        />
      </div>

      <div className="space-y-1 min-w-0">
        <span className="text-xs text-muted-foreground">Config directory</span>
        <div className="flex gap-2 min-w-0">
          <input
            aria-label="Config directory"
            value={configDir}
            onChange={(e) => setConfigDir(e.target.value)}
            placeholder={`${configEnvName} folder`}
            className="flex-1 min-w-0 h-8 rounded-md border bg-background px-2 text-sm font-mono truncate"
          />
          <Button
            type="button"
            variant="outline"
            size="sm"
            className="shrink-0"
            onClick={chooseFolder}
          >
            Choose…
          </Button>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Tip: press ⌘⇧. in the dialog to show hidden folders.
        </p>
      </div>

      <p className="text-xs text-muted-foreground break-words">
        Log in once via the CLI with that folder, e.g.{" "}
        <code className="break-all">
          {configEnvName}=&lt;dir&gt;{" "}
          {providerId === "codex" ? "codex login" : "claude /login"}
        </code>
        . OpenUsage only reads the resulting Keychain session.
      </p>

      <IconPicker value={icon} onChange={setIcon} />

      <div className="flex gap-2">
        <Button
          type="button"
          size="sm"
          className="flex-1"
          disabled={!canSubmit}
          onClick={() => onSubmit(providerId, label.trim(), configDir.trim(), icon)}
        >
          {mode === "add" ? "Add" : "Save"}
        </Button>
        <Button type="button" size="sm" variant="outline" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

function AddAccountForm({
  providers,
  onAddInstance,
}: {
  providers: AddableProvider[];
  onAddInstance: (
    providerId: string,
    label: string,
    configDir: string,
    icon?: string | null
  ) => void;
}) {
  const addable = useMemo(
    () => providers.filter((p) => MULTI_ACCOUNT_PROVIDERS.has(p.id)),
    [providers]
  );
  const [open, setOpen] = useState(false);

  if (addable.length === 0) return null;

  if (!open) {
    return (
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="w-full mt-1"
        onClick={() => setOpen(true)}
      >
        <Plus className="h-4 w-4 mr-1" />
        Add account
      </Button>
    );
  }

  return (
    <AccountForm
      mode="add"
      providers={providers}
      onSubmit={(providerId, label, configDir, icon) => {
        onAddInstance(providerId, label, configDir, icon);
        setOpen(false);
      }}
      onCancel={() => setOpen(false)}
    />
  );
}

interface SettingsPageProps {
  plugins: PluginConfig[];
  onReorder: (orderedIds: string[]) => void;
  onToggle: (id: string) => void;
  onAddInstance: (
    providerId: string,
    label: string,
    configDir: string,
    icon?: string | null
  ) => void;
  onEditInstance: (
    instanceId: string,
    patch: { label: string; configDir: string; icon?: string | null }
  ) => void;
  onRemoveInstance: (instanceId: string) => void;
  addableProviders: AddableProvider[];
  autoUpdateInterval: AutoUpdateIntervalMinutes;
  onAutoUpdateIntervalChange: (value: AutoUpdateIntervalMinutes) => void;
  themeMode: ThemeMode;
  onThemeModeChange: (value: ThemeMode) => void;
  displayMode: DisplayMode;
  onDisplayModeChange: (value: DisplayMode) => void;
  resetTimerDisplayMode: ResetTimerDisplayMode;
  onResetTimerDisplayModeChange: (value: ResetTimerDisplayMode) => void;
  timeFormatMode: TimeFormatMode;
  onTimeFormatModeChange: (value: TimeFormatMode) => void;
  menubarIconStyle: MenubarIconStyle;
  onMenubarIconStyleChange: (value: MenubarIconStyle) => void;
  menubarMetric: MenubarMetric;
  onMenubarMetricChange: (value: MenubarMetric) => void;
  traySettingsPreview: TraySettingsPreview;
  globalShortcut: GlobalShortcut;
  onGlobalShortcutChange: (value: GlobalShortcut) => void;
  startOnLogin: boolean;
  onStartOnLoginChange: (value: boolean) => void;
}

export function SettingsPage({
  plugins,
  onReorder,
  onToggle,
  onAddInstance,
  onEditInstance,
  onRemoveInstance,
  addableProviders,
  autoUpdateInterval,
  onAutoUpdateIntervalChange,
  themeMode,
  onThemeModeChange,
  displayMode,
  onDisplayModeChange,
  resetTimerDisplayMode,
  onResetTimerDisplayModeChange,
  timeFormatMode,
  onTimeFormatModeChange,
  menubarIconStyle,
  onMenubarIconStyleChange,
  menubarMetric,
  onMenubarMetricChange,
  traySettingsPreview,
  globalShortcut,
  onGlobalShortcutChange,
  startOnLogin,
  onStartOnLoginChange,
}: SettingsPageProps) {
  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    })
  );

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;

    if (over && active.id !== over.id) {
      const oldIndex = plugins.findIndex((item) => item.id === active.id);
      const newIndex = plugins.findIndex((item) => item.id === over.id);
      if (oldIndex === -1 || newIndex === -1) return;
      const next = arrayMove(plugins, oldIndex, newIndex);
      onReorder(next.map((item) => item.id));
    }
  };

  const [editingId, setEditingId] = useState<string | null>(null);
  const editingPlugin = plugins.find((p) => p.id === editingId) ?? null;
  const editingConfigDir = editingPlugin?.env
    ? Object.values(editingPlugin.env)[0] ?? ""
    : "";

  return (
    <Tabs defaultValue="general" className="py-3">
      <TabsList className="w-full">
        <TabsTrigger value="general">General</TabsTrigger>
        <TabsTrigger value="appearance">Appearance</TabsTrigger>
        <TabsTrigger value="accounts">Accounts</TabsTrigger>
      </TabsList>

      <TabsContent value="general" className="space-y-4 mt-3">
      <section>
        <h3 className="text-lg font-semibold mb-0">Auto Refresh</h3>
        <p className="text-sm text-muted-foreground mb-2">
          How obsessive are you
        </p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Auto-update interval">
            {AUTO_UPDATE_OPTIONS.map((option) => {
              const isActive = option.value === autoUpdateInterval;
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-checked={isActive}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1"
                  onClick={() => onAutoUpdateIntervalChange(option.value)}
                >
                  {option.label}
                </Button>
              );
            })}
          </div>
        </div>
      </section>
      <section>
        <h3 className="text-lg font-semibold mb-0">Usage Mode</h3>
        <p className="text-sm text-muted-foreground mb-2">
          Glass half full or half empty
        </p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Usage display mode">
            {DISPLAY_MODE_OPTIONS.map((option) => {
              const isActive = option.value === displayMode;
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-checked={isActive}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1"
                  onClick={() => onDisplayModeChange(option.value)}
                >
                  {option.label}
                </Button>
              );
            })}
          </div>
        </div>
      </section>
      <section>
        <h3 className="text-lg font-semibold mb-0">Reset Timers</h3>
        <p className="text-sm text-muted-foreground mb-2">
          Countdown or clock time
        </p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Reset timer display mode">
            {RESET_TIMER_DISPLAY_OPTIONS.map((option) => {
              const isActive = option.value === resetTimerDisplayMode;
              const absoluteTimeExample = getTimeFormatter(timeFormatMode).format(new Date(2026, 1, 2, 11, 4));
              const example = option.value === "relative" ? "5h 12m" : `today at ${absoluteTimeExample}`;
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-checked={isActive}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1 flex flex-col items-center gap-0 py-2 h-auto"
                  onClick={() => onResetTimerDisplayModeChange(option.value)}
                >
                  <span>{option.label}</span>
                  <span
                    className={cn(
                      "text-xs font-normal",
                      isActive ? "text-primary-foreground/80" : "text-muted-foreground"
                    )}
                  >
                    {example}
                  </span>
                </Button>
              );
            })}
          </div>
        </div>
      </section>
      <section>
        <h3 className="text-lg font-semibold mb-0">Time Format</h3>
        <p className="text-sm text-muted-foreground mb-2">
          12-hour or 24-hour clock
        </p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Time format">
            {TIME_FORMAT_OPTIONS.map((option) => {
              const isActive = option.value === timeFormatMode;
              const example = getTimeFormatter(option.value).format(new Date(2026, 1, 2, 11, 4));
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-checked={isActive}
                  aria-label={option.label}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1 flex flex-col items-center gap-0 py-2 h-auto"
                  onClick={() => onTimeFormatModeChange(option.value)}
                >
                  <span>{option.label}</span>
                  <span
                    className={cn(
                      "text-xs font-normal",
                      isActive ? "text-primary-foreground/80" : "text-muted-foreground"
                    )}
                  >
                    {example}
                  </span>
                </Button>
              );
            })}
          </div>
        </div>
      </section>
      <GlobalShortcutSection
        globalShortcut={globalShortcut}
        onGlobalShortcutChange={onGlobalShortcutChange}
      />
      <section>
        <h3 className="text-lg font-semibold mb-0">Start on Login</h3>
        <p className="text-sm text-muted-foreground mb-2">
          OpenUsage starts when you sign in
        </p>
        <label className="flex items-center gap-2 text-sm select-none text-foreground">
          <Checkbox
            key={`start-on-login-${startOnLogin}`}
            checked={startOnLogin}
            onCheckedChange={(checked) => onStartOnLoginChange(checked === true)}
          />
          Start on login
        </label>
      </section>
      </TabsContent>

      <TabsContent value="appearance" className="space-y-4 mt-3">
      <section>
        <h3 className="text-lg font-semibold mb-0">Menubar Icon</h3>
        <p className="text-sm text-muted-foreground mb-2">
          What shows in the menu bar
        </p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Menubar icon style">
            {MENUBAR_ICON_STYLE_OPTIONS.map((option) => {
              const isActive = option.value === menubarIconStyle;
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-label={option.label}
                  aria-checked={isActive}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1 h-9 flex items-center justify-center"
                  onClick={() => onMenubarIconStyleChange(option.value)}
                >
                  <MenubarIconStylePreview
                    style={option.value}
                    isActive={isActive}
                    traySettingsPreview={traySettingsPreview}
                  />
                </Button>
              );
            })}
          </div>
        </div>
        <p className="text-sm text-muted-foreground mt-3 mb-2">Metric</p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Menubar metric">
            {MENUBAR_METRIC_OPTIONS.map((option) => {
              const isActive = option.value === menubarMetric;
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-label={option.label}
                  aria-checked={isActive}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1"
                  onClick={() => onMenubarMetricChange(option.value)}
                >
                  {option.label}
                </Button>
              );
            })}
          </div>
        </div>
      </section>
      <section>
        <h3 className="text-lg font-semibold mb-0">App Theme</h3>
        <p className="text-sm text-muted-foreground mb-2">
          How it looks around here
        </p>
        <div className="bg-muted/50 rounded-lg p-1">
          <div className="flex gap-1" role="radiogroup" aria-label="Theme mode">
            {THEME_OPTIONS.map((option) => {
              const isActive = option.value === themeMode;
              return (
                <Button
                  key={option.value}
                  type="button"
                  role="radio"
                  aria-checked={isActive}
                  variant={isActive ? "default" : "outline"}
                  size="sm"
                  className="flex-1"
                  onClick={() => onThemeModeChange(option.value)}
                >
                  {option.label}
                </Button>
              );
            })}
          </div>
        </div>
      </section>
      </TabsContent>

      <TabsContent value="accounts" className="space-y-4 mt-3">
      <section>
        <h3 className="text-lg font-semibold mb-0">Plugins</h3>
        <p className="text-sm text-muted-foreground mb-2">
          Your AI coding lineup
        </p>
        <div className="bg-muted/50 rounded-lg p-1 space-y-1">
          <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
          >
            <SortableContext
              items={plugins.map((p) => p.id)}
              strategy={verticalListSortingStrategy}
            >
              {plugins.map((plugin) => (
                <Fragment key={plugin.id}>
                  <SortablePluginItem
                    plugin={plugin}
                    onToggle={onToggle}
                    onRemove={onRemoveInstance}
                    onEdit={(id) => setEditingId(id)}
                  />
                  {editingPlugin && editingPlugin.id === plugin.id ? (
                    <AccountForm
                      mode="edit"
                      providers={addableProviders}
                      initial={{
                        providerId: editingPlugin.providerId,
                        providerName: editingPlugin.name,
                        label: editingPlugin.label ?? "",
                        configDir: editingConfigDir,
                        icon: editingPlugin.icon ?? null,
                      }}
                      onSubmit={(_providerId, label, configDir, icon) => {
                        onEditInstance(editingPlugin.id, {
                          label,
                          configDir,
                          icon,
                        });
                        setEditingId(null);
                      }}
                      onCancel={() => setEditingId(null)}
                    />
                  ) : null}
                </Fragment>
              ))}
            </SortableContext>
          </DndContext>
          {!editingPlugin ? (
            <AddAccountForm
              providers={addableProviders}
              onAddInstance={onAddInstance}
            />
          ) : null}
        </div>
      </section>
      </TabsContent>
    </Tabs>
  );
}
