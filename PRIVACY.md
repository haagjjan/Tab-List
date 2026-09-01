# Tab-List Privacy

Last updated: August 27, 2026

Tab-List performs window switching locally on your Mac. It has no user account, analytics, advertising, cloud synchronization, or automatic crash-report upload.

## Data the app accesses

Tab-List uses Accessibility access to enumerate, focus, raise, and close windows and to observe the configured global keyboard shortcut. It may read:

- Application names and bundle identifiers.
- Window identifiers, geometry, state, and titles.
- The currently focused application and window.
- Global key events needed for the active shortcut session.

Tab-List does not capture window content. It never requests Screen Recording access and links no screen-capture API.

## Storage

- Application icons may be cached under the app's macOS Caches directory. Icons do not contain window content.
- Preferences contain theme, filtering, shortcut, and excluded-application settings.
- Ephemeral macOS window identifiers and MRU state are not persisted across launches.
- Normal logs redact window titles.

macOS or development tools may independently create system diagnostics, virtual-memory pages, or crash logs outside Tab-List's control. Tab-List does not upload them.

## Network access

Network access is limited to update checks and downloads through Sparkle from the project's GitHub Releases feed. GitHub and its infrastructure receive ordinary network metadata such as IP address and user agent when an update request is made. Refer to GitHub's privacy statement for its handling of that data.

Tab-List does not transmit window titles, installed-application lists, shortcuts, or diagnostics.

## Diagnostics

Diagnostics are generated only after an explicit user action. The export omits window titles entirely and hashes bundle identifiers with a salt generated for that single export, so two exports of the same window produce different pseudonyms. Review an export before sharing it because system configuration can still be identifying.

## Permissions and control

- Accessibility is the only permission Tab-List requests. Without it the switcher does nothing and says so.
- Launch at Login is off by default and changes only after an explicit user action.
- Permissions can be revoked at any time in System Settings. Tab-List stops all affected behavior and surfaces the resulting state without repeatedly prompting.
- Preferences and icon caches can be removed by deleting the app's preferences and cache data.

## Changes and questions

Material privacy changes will be documented in the release notes and this file. Open a GitHub issue for general privacy questions. Report a security or privacy vulnerability privately using the process in [SECURITY.md](SECURITY.md).
