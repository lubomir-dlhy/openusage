/**
 * Built-in custom-icon presets selectable in the add/edit account form.
 * Each `dataUrl` is a self-contained image (SVG/PNG data URL) shown full-color in
 * the app (nav rail + provider cards) for an account whose `icon` is set to it.
 *
 * Empty by default — users set a per-account icon via the form's Upload button.
 * Add entries here to ship reusable built-in presets.
 */
export type AccountIconPreset = {
  id: string;
  label: string;
  dataUrl: string;
};

export const ACCOUNT_ICON_PRESETS: AccountIconPreset[] = [];
