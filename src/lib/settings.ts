import { LazyStore } from "@tauri-apps/plugin-store";
import type { PluginMeta } from "@/lib/plugin-types";

// Refresh cooldown duration in milliseconds (5 minutes)
export const REFRESH_COOLDOWN_MS = 300_000;

/**
 * A single account instance of a provider. The default account for a provider
 * has `instanceId === providerId` and no env override. Extra accounts get a
 * distinct `instanceId` (e.g. "claude#2") and an `env` pointing at that
 * account's config directory.
 *
 * `env` holds directory PATHS only (e.g. CLAUDE_CONFIG_DIR / CODEX_HOME) — never
 * a credential. Tokens stay in the macOS Keychain, written by the official CLIs.
 */
export type PluginInstance = {
  instanceId: string;
  providerId: string;
  label?: string | null;
  env?: Record<string, string>;
  /**
   * Optional custom icon (a data URL or image URL) shown full-color in-app
   * (nav rail + provider cards) for this account. When absent, the provider's
   * default icon is used. The menu-bar (tray) icon always uses the provider glyph.
   */
  icon?: string | null;
};

// Spec: persist plugin order + disabled list (keyed by instanceId; for default
// accounts instanceId === providerId so legacy id-keyed data still applies).
// `instances` holds the per-account definitions. New plugins append, default
// disabled unless in DEFAULT_ENABLED_PLUGINS.
export type PluginSettings = {
  order: string[];
  disabled: string[];
  instances: PluginInstance[];
};

/** Shape sent to the Rust `start_probe_batch` command for each account. */
export type ProbeInstance = {
  pluginId: string;
  instanceId: string;
  label?: string | null;
  env?: Record<string, string>;
};

/** Env var used to point a provider at a specific account's config directory. */
export const PROVIDER_CONFIG_DIR_ENV: Record<string, string> = {
  claude: "CLAUDE_CONFIG_DIR",
  codex: "CODEX_HOME",
};

export type AutoUpdateIntervalMinutes = 5 | 15 | 30 | 60;

export type ThemeMode = "system" | "light" | "dark";

export type DisplayMode = "used" | "left";

export type ResetTimerDisplayMode = "relative" | "absolute";

export type TimeFormatMode = "auto" | "12h" | "24h";

export type MenubarIconStyle = "provider" | "bars" | "donut";

export type MenubarMetric = "default" | "weekly";

export type GlobalShortcut = string | null;

const SETTINGS_STORE_PATH = "settings.json";
const PLUGIN_SETTINGS_KEY = "plugins";
const AUTO_UPDATE_SETTINGS_KEY = "autoUpdateInterval";
const THEME_MODE_KEY = "themeMode";
const DISPLAY_MODE_KEY = "displayMode";
const RESET_TIMER_DISPLAY_MODE_KEY = "resetTimerDisplayMode";
const TIME_FORMAT_MODE_KEY = "timeFormatMode";
const MENUBAR_ICON_STYLE_KEY = "menubarIconStyle";
const MENUBAR_METRIC_KEY = "menubarMetric";
const LEGACY_TRAY_ICON_STYLE_KEY = "trayIconStyle";
const LEGACY_TRAY_SHOW_PERCENTAGE_KEY = "trayShowPercentage";
const GLOBAL_SHORTCUT_KEY = "globalShortcut";
const START_ON_LOGIN_KEY = "startOnLogin";
const RETIREMENT_NOTICE_DISMISSED_AT_KEY = "retirementNoticeDismissedAt";

// How long a dismissal lasts before the retirement notice is shown again (7 days).
export const RETIREMENT_NOTICE_INTERVAL_MS = 7 * 24 * 60 * 60 * 1000;

export const DEFAULT_AUTO_UPDATE_INTERVAL: AutoUpdateIntervalMinutes = 15;
export const DEFAULT_THEME_MODE: ThemeMode = "system";
export const DEFAULT_DISPLAY_MODE: DisplayMode = "left";
export const DEFAULT_RESET_TIMER_DISPLAY_MODE: ResetTimerDisplayMode = "relative";
export const DEFAULT_TIME_FORMAT_MODE: TimeFormatMode = "auto";
export const DEFAULT_MENUBAR_ICON_STYLE: MenubarIconStyle = "provider";
export const DEFAULT_MENUBAR_METRIC: MenubarMetric = "default";
export const DEFAULT_GLOBAL_SHORTCUT: GlobalShortcut = null;
export const DEFAULT_START_ON_LOGIN = false;

const AUTO_UPDATE_INTERVALS: AutoUpdateIntervalMinutes[] = [5, 15, 30, 60];
const THEME_MODES: ThemeMode[] = ["system", "light", "dark"];
const DISPLAY_MODES: DisplayMode[] = ["used", "left"];
const RESET_TIMER_DISPLAY_MODES: ResetTimerDisplayMode[] = ["relative", "absolute"];
const TIME_FORMAT_MODES: TimeFormatMode[] = ["auto", "12h", "24h"];
const MENUBAR_ICON_STYLES: MenubarIconStyle[] = ["provider", "donut", "bars"];
const MENUBAR_METRICS: MenubarMetric[] = ["default", "weekly"];

export const MENUBAR_ICON_STYLE_OPTIONS: { value: MenubarIconStyle; label: string }[] = [
  { value: "provider", label: "Plugin" },
  { value: "donut", label: "Donut" },
  { value: "bars", label: "Bars" },
];

export const MENUBAR_METRIC_OPTIONS: { value: MenubarMetric; label: string }[] = [
  { value: "default", label: "Default" },
  { value: "weekly", label: "Weekly" },
];

export const AUTO_UPDATE_OPTIONS: { value: AutoUpdateIntervalMinutes; label: string }[] =
  AUTO_UPDATE_INTERVALS.map((value) => ({
    value,
    label: value === 60 ? "1 hour" : `${value} min`,
  }));

export const THEME_OPTIONS: { value: ThemeMode; label: string }[] =
  THEME_MODES.map((value) => ({
    value,
    label: value.charAt(0).toUpperCase() + value.slice(1),
  }));

export const DISPLAY_MODE_OPTIONS: { value: DisplayMode; label: string }[] = [
  { value: "left", label: "Left" },
  { value: "used", label: "Used" },
];

export const RESET_TIMER_DISPLAY_OPTIONS: { value: ResetTimerDisplayMode; label: string }[] = [
  { value: "relative", label: "Relative" },
  { value: "absolute", label: "Absolute" },
];

export const TIME_FORMAT_OPTIONS: { value: TimeFormatMode; label: string }[] = [
  { value: "auto", label: "Auto" },
  { value: "12h", label: "12-hour" },
  { value: "24h", label: "24-hour" },
];

const store = new LazyStore(SETTINGS_STORE_PATH);

const DEFAULT_ENABLED_PLUGINS = new Set(["claude", "codex", "cursor"]);

export const DEFAULT_PLUGIN_SETTINGS: PluginSettings = {
  order: [],
  disabled: [],
  instances: [],
};

function isValidInstance(value: unknown): value is PluginInstance {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return typeof v.instanceId === "string" && typeof v.providerId === "string";
}

/**
 * Ensure every id referenced in `order` has a matching instance definition.
 * Legacy installs (and order entries with no instance) get a synthesized
 * default instance where instanceId === providerId and there is no env override.
 */
function withSynthesizedInstances(settings: PluginSettings): PluginSettings {
  const byId = new Map(
    (settings.instances ?? []).map((inst) => [inst.instanceId, inst])
  );
  for (const id of settings.order) {
    if (!byId.has(id)) {
      byId.set(id, { instanceId: id, providerId: id });
    }
  }
  return { ...settings, instances: Array.from(byId.values()) };
}

export async function loadPluginSettings(): Promise<PluginSettings> {
  const stored = await store.get<PluginSettings>(PLUGIN_SETTINGS_KEY);
  if (!stored) return { ...DEFAULT_PLUGIN_SETTINGS, instances: [] };
  const order = Array.isArray(stored.order) ? stored.order : [];
  const disabled = Array.isArray(stored.disabled) ? stored.disabled : [];
  const instances = Array.isArray(stored.instances)
    ? stored.instances.filter(isValidInstance)
    : [];
  return withSynthesizedInstances({ order, disabled, instances });
}

export async function savePluginSettings(settings: PluginSettings): Promise<void> {
  await store.set(PLUGIN_SETTINGS_KEY, settings);
  await store.save();
}

/** Map of instanceId -> instance for the given settings. */
function instancesById(settings: PluginSettings): Map<string, PluginInstance> {
  return new Map((settings.instances ?? []).map((inst) => [inst.instanceId, inst]));
}

/**
 * Expand a list of enabled instanceIds into the ProbeInstance objects sent to
 * Rust. When `instanceIds` is omitted, all enabled instances are returned.
 */
export function resolveProbeInstances(
  settings: PluginSettings,
  instanceIds?: string[]
): ProbeInstance[] {
  const byId = instancesById(settings);
  const ids = instanceIds ?? getEnabledPluginIds(settings);
  return ids.map((id) => {
    const inst = byId.get(id);
    if (!inst) {
      // Defensive: treat an unknown id as a default account (instanceId == providerId).
      return { pluginId: id, instanceId: id };
    }
    return {
      pluginId: inst.providerId,
      instanceId: inst.instanceId,
      label: inst.label ?? null,
      env: inst.env,
    };
  });
}

/** Generate a stable, collision-free instanceId for a new account. */
function nextInstanceId(settings: PluginSettings, providerId: string): string {
  const existing = new Set(settings.instances.map((inst) => inst.instanceId));
  existing.add(providerId); // the default account already owns the bare providerId
  let n = 2;
  let candidate = `${providerId}#${n}`;
  while (existing.has(candidate)) {
    n += 1;
    candidate = `${providerId}#${n}`;
  }
  return candidate;
}

/** Add a new account instance for a provider (enabled by default). */
export function addInstance(
  settings: PluginSettings,
  providerId: string,
  label: string | null,
  env?: Record<string, string>,
  icon?: string | null
): PluginSettings {
  const instanceId = nextInstanceId(settings, providerId);
  const instance: PluginInstance = {
    instanceId,
    providerId,
    label: label && label.trim() ? label.trim() : null,
    ...(env && Object.keys(env).length > 0 ? { env } : {}),
    ...(icon ? { icon } : {}),
  };
  return {
    order: [...settings.order, instanceId],
    disabled: settings.disabled,
    instances: [...settings.instances, instance],
  };
}

/**
 * Update an existing account instance. Only the keys present in `patch` are
 * changed. Passing `icon: null/undefined` clears the custom icon; passing
 * `env` replaces the env map. Returns the same settings object if no instance
 * matches (callers can use referential equality to detect a no-op).
 */
export function editInstance(
  settings: PluginSettings,
  instanceId: string,
  patch: { label?: string | null; env?: Record<string, string>; icon?: string | null }
): PluginSettings {
  let changed = false;
  const instances = settings.instances.map((inst) => {
    if (inst.instanceId !== instanceId) return inst;
    changed = true;
    const next: PluginInstance = { ...inst };
    if ("label" in patch) {
      const trimmed = patch.label && patch.label.trim() ? patch.label.trim() : null;
      next.label = trimmed;
    }
    if ("env" in patch) {
      if (patch.env && Object.keys(patch.env).length > 0) next.env = patch.env;
      else delete next.env;
    }
    if ("icon" in patch) {
      if (patch.icon) next.icon = patch.icon;
      else delete next.icon;
    }
    return next;
  });
  if (!changed) return settings;
  return { ...settings, instances };
}

/**
 * Remove an extra account instance. Default accounts (instanceId === providerId)
 * are never removed through this path — disable them instead.
 */
export function removeInstance(
  settings: PluginSettings,
  instanceId: string
): PluginSettings {
  const inst = settings.instances.find((i) => i.instanceId === instanceId);
  if (!inst || inst.instanceId === inst.providerId) return settings;
  return {
    order: settings.order.filter((id) => id !== instanceId),
    disabled: settings.disabled.filter((id) => id !== instanceId),
    instances: settings.instances.filter((i) => i.instanceId !== instanceId),
  };
}

// TODO(remove after 2026-09-01): One-time Windsurf -> Devin settings migration.
export function migrateWindsurfToDevin(settings: PluginSettings): PluginSettings {
  const hasDevin = settings.order.includes("devin");
  const hasWindsurf = settings.order.includes("windsurf");
  const windsurfWasDisabled = settings.disabled.includes("windsurf");
  const order = Array.from(
    new Set(settings.order.map((id) => (id === "windsurf" ? "devin" : id)))
  );
  let disabled = settings.disabled.filter((id) => id !== "windsurf");

  if (hasWindsurf && !windsurfWasDisabled) {
    disabled = disabled.filter((id) => id !== "devin");
  }

  if (!hasDevin && windsurfWasDisabled && !disabled.includes("devin")) {
    disabled.push("devin");
  }

  // Remap any windsurf instances to devin (default instance only; extra windsurf
  // accounts are dropped by normalize since the provider is retired).
  const instances = (settings.instances ?? [])
    .map((inst) =>
      inst.providerId === "windsurf"
        ? {
            ...inst,
            providerId: "devin",
            instanceId: inst.instanceId === "windsurf" ? "devin" : inst.instanceId,
          }
        : inst
    )
    .filter(
      (inst, index, all) =>
        all.findIndex((other) => other.instanceId === inst.instanceId) === index
    );

  return withSynthesizedInstances({
    order,
    disabled: Array.from(new Set(disabled)),
    instances,
  });
}

function isAutoUpdateInterval(value: unknown): value is AutoUpdateIntervalMinutes {
  return (
    typeof value === "number" &&
    AUTO_UPDATE_INTERVALS.includes(value as AutoUpdateIntervalMinutes)
  );
}

export async function loadAutoUpdateInterval(): Promise<AutoUpdateIntervalMinutes> {
  const stored = await store.get<unknown>(AUTO_UPDATE_SETTINGS_KEY);
  if (isAutoUpdateInterval(stored)) return stored;
  return DEFAULT_AUTO_UPDATE_INTERVAL;
}

export async function saveAutoUpdateInterval(
  interval: AutoUpdateIntervalMinutes
): Promise<void> {
  await store.set(AUTO_UPDATE_SETTINGS_KEY, interval);
  await store.save();
}

export function normalizePluginSettings(
  settings: PluginSettings,
  plugins: PluginMeta[]
): PluginSettings {
  const knownProviderIds = new Set(plugins.map((plugin) => plugin.id));

  // Index instances by id, ensuring a default instance for every known provider
  // and dropping instances whose provider is no longer available (e.g. retired).
  const instById = new Map<string, PluginInstance>();
  for (const inst of settings.instances ?? []) {
    if (knownProviderIds.has(inst.providerId)) {
      instById.set(inst.instanceId, inst);
    }
  }
  for (const providerId of knownProviderIds) {
    if (!instById.has(providerId)) {
      instById.set(providerId, { instanceId: providerId, providerId });
    }
  }

  const order: string[] = [];
  const seen = new Set<string>();
  for (const id of settings.order) {
    if (!instById.has(id) || seen.has(id)) continue;
    seen.add(id);
    order.push(id);
  }
  const newlyAdded: string[] = [];
  for (const instanceId of instById.keys()) {
    if (!seen.has(instanceId)) {
      seen.add(instanceId);
      order.push(instanceId);
      newlyAdded.push(instanceId);
    }
  }

  const disabled = settings.disabled.filter((id) => instById.has(id));
  for (const instanceId of newlyAdded) {
    const inst = instById.get(instanceId)!;
    const isDefault = inst.instanceId === inst.providerId;
    // Default accounts follow the DEFAULT_ENABLED_PLUGINS gate; extra accounts
    // (added explicitly by the user) default to enabled.
    if (
      isDefault &&
      !DEFAULT_ENABLED_PLUGINS.has(inst.providerId) &&
      !disabled.includes(instanceId)
    ) {
      disabled.push(instanceId);
    }
  }
  return { order, disabled, instances: Array.from(instById.values()) };
}

function areInstancesEqual(a: PluginInstance, b: PluginInstance): boolean {
  if (a.instanceId !== b.instanceId) return false;
  if (a.providerId !== b.providerId) return false;
  if ((a.label ?? null) !== (b.label ?? null)) return false;
  if ((a.icon ?? null) !== (b.icon ?? null)) return false;
  return JSON.stringify(a.env ?? null) === JSON.stringify(b.env ?? null);
}

export function arePluginSettingsEqual(
  a: PluginSettings,
  b: PluginSettings
): boolean {
  if (a.order.length !== b.order.length) return false;
  if (a.disabled.length !== b.disabled.length) return false;
  const aInstances = a.instances ?? [];
  const bInstances = b.instances ?? [];
  if (aInstances.length !== bInstances.length) return false;
  for (let i = 0; i < a.order.length; i += 1) {
    if (a.order[i] !== b.order[i]) return false;
  }
  for (let i = 0; i < a.disabled.length; i += 1) {
    if (a.disabled[i] !== b.disabled[i]) return false;
  }
  for (let i = 0; i < aInstances.length; i += 1) {
    if (!areInstancesEqual(aInstances[i], bInstances[i])) return false;
  }
  return true;
}

function isThemeMode(value: unknown): value is ThemeMode {
  return typeof value === "string" && THEME_MODES.includes(value as ThemeMode);
}

export async function loadThemeMode(): Promise<ThemeMode> {
  const stored = await store.get<unknown>(THEME_MODE_KEY);
  if (isThemeMode(stored)) return stored;
  return DEFAULT_THEME_MODE;
}

export async function saveThemeMode(mode: ThemeMode): Promise<void> {
  await store.set(THEME_MODE_KEY, mode);
  await store.save();
}

function isDisplayMode(value: unknown): value is DisplayMode {
  return typeof value === "string" && DISPLAY_MODES.includes(value as DisplayMode);
}

export async function loadDisplayMode(): Promise<DisplayMode> {
  const stored = await store.get<unknown>(DISPLAY_MODE_KEY);
  if (isDisplayMode(stored)) return stored;
  return DEFAULT_DISPLAY_MODE;
}

export async function saveDisplayMode(mode: DisplayMode): Promise<void> {
  await store.set(DISPLAY_MODE_KEY, mode);
  await store.save();
}

function isResetTimerDisplayMode(value: unknown): value is ResetTimerDisplayMode {
  return (
    typeof value === "string" &&
    RESET_TIMER_DISPLAY_MODES.includes(value as ResetTimerDisplayMode)
  );
}

export async function loadResetTimerDisplayMode(): Promise<ResetTimerDisplayMode> {
  const stored = await store.get<unknown>(RESET_TIMER_DISPLAY_MODE_KEY);
  if (isResetTimerDisplayMode(stored)) return stored;
  return DEFAULT_RESET_TIMER_DISPLAY_MODE;
}

export async function saveResetTimerDisplayMode(mode: ResetTimerDisplayMode): Promise<void> {
  await store.set(RESET_TIMER_DISPLAY_MODE_KEY, mode);
  await store.save();
}

function isTimeFormatMode(value: unknown): value is TimeFormatMode {
  return (
    typeof value === "string" &&
    TIME_FORMAT_MODES.includes(value as TimeFormatMode)
  );
}

export async function loadTimeFormatMode(): Promise<TimeFormatMode> {
  const stored = await store.get<unknown>(TIME_FORMAT_MODE_KEY);
  if (isTimeFormatMode(stored)) return stored;
  return DEFAULT_TIME_FORMAT_MODE;
}

export async function saveTimeFormatMode(mode: TimeFormatMode): Promise<void> {
  await store.set(TIME_FORMAT_MODE_KEY, mode);
  await store.save();
}

function isMenubarIconStyle(value: unknown): value is MenubarIconStyle {
  return (
    typeof value === "string" &&
    MENUBAR_ICON_STYLES.includes(value as MenubarIconStyle)
  );
}

export async function loadMenubarIconStyle(): Promise<MenubarIconStyle> {
  const stored = await store.get<unknown>(MENUBAR_ICON_STYLE_KEY);
  if (isMenubarIconStyle(stored)) return stored;
  return DEFAULT_MENUBAR_ICON_STYLE;
}

export async function saveMenubarIconStyle(style: MenubarIconStyle): Promise<void> {
  await store.set(MENUBAR_ICON_STYLE_KEY, style);
  await store.save();
}

function isMenubarMetric(value: unknown): value is MenubarMetric {
  return typeof value === "string" && MENUBAR_METRICS.includes(value as MenubarMetric);
}

export async function loadMenubarMetric(): Promise<MenubarMetric> {
  const stored = await store.get<unknown>(MENUBAR_METRIC_KEY);
  if (isMenubarMetric(stored)) return stored;
  return DEFAULT_MENUBAR_METRIC;
}

export async function saveMenubarMetric(metric: MenubarMetric): Promise<void> {
  await store.set(MENUBAR_METRIC_KEY, metric);
  await store.save();
}

type LegacyStoreWithDelete = {
  delete?: (key: string) => Promise<void>;
};

async function deleteStoreKey(key: string): Promise<void> {
  const maybeDelete = (store as unknown as LegacyStoreWithDelete).delete;
  if (typeof maybeDelete === "function") {
    await maybeDelete.call(store, key);
    return;
  }
  // Fallback for store implementations without delete support.
  await store.set(key, null);
}

export async function migrateLegacyTraySettings(): Promise<void> {
  const [legacyTrayStyle, legacyShowPercentage, currentMenubarStyle] = await Promise.all([
    store.get<unknown>(LEGACY_TRAY_ICON_STYLE_KEY),
    store.get<unknown>(LEGACY_TRAY_SHOW_PERCENTAGE_KEY),
    store.get<unknown>(MENUBAR_ICON_STYLE_KEY),
  ]);

  const hasLegacyTrayStyle = legacyTrayStyle != null;
  const hasLegacyShowPercentage = legacyShowPercentage != null;
  if (!hasLegacyTrayStyle && !hasLegacyShowPercentage) return;

  if (hasLegacyTrayStyle && currentMenubarStyle == null) {
    if (legacyTrayStyle === "bars") {
      await store.set(MENUBAR_ICON_STYLE_KEY, "bars");
    } else if (legacyTrayStyle === "circle") {
      await store.set(MENUBAR_ICON_STYLE_KEY, "donut");
    }
  }

  const removals: Promise<void>[] = [];
  if (hasLegacyTrayStyle) removals.push(deleteStoreKey(LEGACY_TRAY_ICON_STYLE_KEY));
  if (hasLegacyShowPercentage) removals.push(deleteStoreKey(LEGACY_TRAY_SHOW_PERCENTAGE_KEY));
  await Promise.all(removals);
  await store.save();
}

export function getEnabledPluginIds(settings: PluginSettings): string[] {
  const disabledSet = new Set(settings.disabled);
  return settings.order.filter((id) => !disabledSet.has(id));
}

function isGlobalShortcut(value: unknown): value is GlobalShortcut {
  if (value === null) return true;
  return typeof value === "string";
}

export async function loadGlobalShortcut(): Promise<GlobalShortcut> {
  const stored = await store.get<unknown>(GLOBAL_SHORTCUT_KEY);
  if (isGlobalShortcut(stored)) return stored;
  return DEFAULT_GLOBAL_SHORTCUT;
}

export async function saveGlobalShortcut(shortcut: GlobalShortcut): Promise<void> {
  await store.set(GLOBAL_SHORTCUT_KEY, shortcut);
  await store.save();
}

export async function loadStartOnLogin(): Promise<boolean> {
  const stored = await store.get<unknown>(START_ON_LOGIN_KEY);
  if (typeof stored === "boolean") return stored;
  return DEFAULT_START_ON_LOGIN;
}

export async function saveStartOnLogin(value: boolean): Promise<void> {
  await store.set(START_ON_LOGIN_KEY, value);
  await store.save();
}

export async function loadRetirementNoticeDismissedAt(): Promise<number | null> {
  const stored = await store.get<unknown>(RETIREMENT_NOTICE_DISMISSED_AT_KEY);
  if (typeof stored === "number" && Number.isFinite(stored) && stored >= 0) {
    return stored;
  }
  return null;
}

export async function saveRetirementNoticeDismissedAt(value: number): Promise<void> {
  await store.set(RETIREMENT_NOTICE_DISMISSED_AT_KEY, value);
  await store.save();
}

export function shouldShowRetirementNotice(
  dismissedAt: number | null,
  now: number
): boolean {
  if (dismissedAt == null) return true;
  // A dismissal in the future (clock skew or a manual settings edit) is
  // invalid; show the notice instead of hiding it indefinitely.
  if (dismissedAt > now) return true;
  return now - dismissedAt >= RETIREMENT_NOTICE_INTERVAL_MS;
}
