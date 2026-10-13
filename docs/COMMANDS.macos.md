# macOS behavior and Tangler

These handwritten notes record macOS features the project uses, drives, replaces, or works around. See [COMMANDS.md](COMMANDS.md) for command IDs and default bindings.

How to read the evidence:

- **Dated observations** were measured on the user's Mac: macOS 26.6.1, one 2560×1440 display, Dock on the right. Detailed probes and historical records remain in development. These observations are not revalidated automatically for each release.
- **Code** means behavior read from `Sources/`, without a separate live measurement.
- **Untested** means it has not been measured and must not be treated as established behavior.
- System shortcuts and gestures marked with ＊ are conventional macOS defaults, not individually verified on this Mac; users may have changed them.

Terminology: a **desktop** is a macOS Space; the **Spaces bar** is the desktop strip at the top of Mission Control. **Accessibility** means the `AX…` APIs that require permission in System Settings. **Private APIs** are undocumented Apple functions or fields that can change with macOS. The default **leader key** is held right Command.

## System features

| System feature | Native entry point | Tangler command or behavior | Implementation | Evidence and limits |
|---|---|---|---|---|
| Mission Control | ⌃↑＊, F3＊, swipe up＊ | No direct command. Tangler opens/closes it for desktop creation, removal, and switching to empty desktops. Tab bars hide while it is open. | Private toggle; Accessibility reads Dock's Spaces bar; Dock sends state notifications. | 2026-10-10: opens/closes 0.1–0.2 s after request. 2026-10-11: open notification about 0.27 s late, close about 0.25 s late, delaying bar hiding/restoration. Desktop operations are rejected while the user has Mission Control open (code). |
| App Exposé | ⌃↓＊, swipe down＊ | No command; tab bars hide while open. | Dock notifications. | Notifications observed on 2026-10-11. No fallback if the end notification is lost; bars may remain hidden until Mission Control next opens/closes. |
| Show Desktop | F11＊, spread gesture＊ | No command; tab bars hide while open. | Dock notifications. | Same limitation as App Exposé. User confirmed hiding/restoration worked on 2026-10-12. |
| Create desktop | Spaces bar + button | `layout.desktopNew` (D N); `workspace.open` (W digit) also creates a desktop for an unopened workspace. | Open Mission Control, press Add Desktop through Accessibility, verify the window-server desktop list. | 2026-10-10: appeared at the end within 20 ms, 9/9 successes. 2026-10-11: a new desktop's button title stayed empty briefly. D N itself was not tested in the installed App. |
| Remove desktop | Hover a desktop and click × in Mission Control＊ | `layout.desktopRemove` (D X); a workspace-owned desktop is saved and released first. | `AXRemoveDesktop` on its Spaces bar button. | 2026-10-10: 8/8 with expanded bar and 1/1 with collapsed bar. macOS moves its windows to a neighboring desktop (code comment). `liveTheCurrentDesktopCanBeRemoved` exists without a run record; installed D X remains untested. |
| Clean up empty desktops | — | `layout.desktopCleanEmpty` (D C), or search “清理所有空桌面”. Scans every display; keeps at least one ordinary desktop per display and leaves full-screen Spaces alone. | Window-server membership plus a complete Accessibility window read, followed by guarded `AXRemoveDesktop`; rechecks after the bar settles and on retries. | Code and automated regression coverage. Hidden/minimized windows and windows assigned to multiple desktops protect their desktops; unknown membership preserves desktops and reports a reason. Desktop elements and Tangler overlays are excluded. Installed command and live bulk cleanup remain untested. |
| Switch desktop | ⌃←/⌃→, enabled ⌃digit shortcuts＊, horizontal swipe＊ | `layout.desktopPrevious` (D [), `layout.desktopNext` (D ]), `layout.desktopSwitch` (D digit); optional interception of system shortcuts below. | Try synthetic Dock swipes one desktop at a time, focusing a target-desktop window, then pressing its Mission Control button. | 2026-10-12: swipe 47 ms/step versus system ⌃←/→ at 536–702 ms; live test 0.11 s out, 0.20 s back. Button switching reliable only after creating a desktop in the same Mission Control session (2026-10-10). Installed D commands untested. |
| Move window to another desktop | Drag to a screen edge or in Mission Control＊ | `layout.spaceLeft` (S ←), `layout.spaceRight` (S →), `layout.spaceNumber` (S digit); reopening workspaces moves existing windows. | Private API available since macOS 26.4, followed by window-server verification. | Requires macOS 26.4+ and Displays have separate Spaces (code). 2026-10-11: reopening a workspace moved two Finder windows to the new desktop in 0.7 s total. S commands themselves untested. |
| Full-screen Space | Green window button＊ | No command. D digit and S digit count normal desktops only; swipe switching counts a full-screen Space as one step. | Desktop-list type information. | Code. Matching Spaces bar buttons to desktop entries with full-screen Spaces is untested. |
| Native window tiling | Drag to screen edges/menu bar, hold ⌥ while dragging; System Settings → Desktop & Dock → Windows | Tangler drag snapping and Option grid can conflict with native tiling. | Read three system settings; warn in Layout without changing them. | Code. Native tiling was off on this Mac on 2026-10-09. System-tiled windows bypass Tangler layout, so tab-group areas use the observed window frame. |
| Application switching | ⌘Tab, ⇧⌘Tab | `switcher.allWindows`, `switcher.allWindowsReverse`: switch windows rather than applications. | Disable these system hotkeys through a private API and handle them in Tangler. | Code; no timing record. 2026-10-09: with Sunlogin in front, keys went to the remote computer instead of Tangler. |
| Same-app window switching | ⌘` | `switcher.appWindows` (⌘`), `switcher.appWindowsReverse` (⇧⌘`) | Same hotkey interception. | Code; no measurement record. |
| Bring only one window forward | Click the window | Click a tab; `tabs.next` (]), `tabs.previous` ([), `tabs.select` (T digit); select in the switcher. | Private calls used by Dock; fallback activates the app and raises the window. | 2026-10-10: two temporary test apps showed only the chosen window was raised. The public fallback previously raised all app windows; that was fixed. |
| Dock icon click | Click | Dock Preview click behavior: system default, minimize current window, or hide application; applies only to the frontmost app's icon. | Observe mouse down/up without intercepting; act after Dock's normal handling. Read icon geometry through Accessibility. | Code; no measurement record. |
| Dock hover | App name and magnification | Show window thumbnails; optionally hide Dock's own app-name label. | Poll which icon is under the pointer; suppress pointer-move events in the icon region to hide labels. | 2026-10-09, right-side Dock: an 8 pt margin suppressed names and also magnification. Label suppression has no effect with Dock autohide (code). |
| Dock placement and autohide | System Settings → Desktop & Dock | Place previews next to the Dock edge. | Infer the edge from icon-list orientation; read autohide preference. | Code. This Mac had a right-side Dock, magnification on, autohide off (2026-10-09). |
| Accessibility permission | System Settings → Privacy & Security → Accessibility | Diagnostics guides permission setup. Window access, desktop operations, and key interception require it. | Public query/prompt APIs; the button opens the relevant settings page. | Code. Stable signing identity can reduce repeated authorization; actual behavior depends on system permission state. |
| Screen Recording permission | System Settings → Privacy & Security → Screen Recording | Required for switcher/Dock thumbnails. Workspace previews do not capture screenshots and do not need it. | Public query/request APIs and ScreenCaptureKit. | Code. Without permission, thumbnails are empty; other functionality remains available. |
| Launch at login | System Settings → General → Login Items | General settings toggle. | Public `SMAppService` API. | Code. When approval is needed, prompt the user to allow it in Login Items. |
| Automatically rearrange Spaces based on most recent use | System Settings → Desktop & Dock | Neither read nor changed; desktops identified by UUID, not position. | — | 2026-10-11: focusing a window switched desktops and moved the target desktop to the end of the system list. |
| Displays have separate Spaces | System Settings → Desktop & Dock | Moving between desktops and creating/removing desktops are unavailable when disabled; report the reason. | Window-server desktop list, with preference as fallback. | Code. Changing this setting requires logging in again (code comment). Disabled configuration untested. |
| Multiple displays | — | `layout.displayLeft`, `layout.displayRight`, `layout.displayUp`, `layout.displayDown` (D + arrow) | Public display enumeration; Dock swipe affects the display under the pointer. | Untested: only one display available. |
| Stage Manager | Control Center＊ | No integration. | Not handled. | Untested. |
| Screen lock and fast user switching | — | Reject desktop operations and synthetic gestures while locked; report screen locked. | Login-session state, using an undocumented lock key. | Code. Live test observed unlocked state on 2026-10-11. |
| Reduce Motion / Increase Contrast | System Settings → Accessibility → Display | Reduce Motion disables Liquid Glass and tab-bar animations; Increase Contrast adds outlines to selected glass cards and active tabs. | SwiftUI environment values. | Code; contrast screenshots exist in the appearance gallery. |
| Liquid Glass material | Native to macOS 26 | Classic and Liquid Glass appearances in Settings → General → Appearance. | Public APIs confined to skin files in `Sources/OverlayKit`. | Code. Tangler does not become the active application; tinted glass turns gray in that context, so glass is untinted (code comment). |

## System shortcuts

| Keys | System behavior | Tangler handling | Effect on the native shortcut | Restore native behavior |
|---|---|---|---|---|
| ⌘Tab, ⇧⌘Tab | Application switching | Switcher intercepts on startup and switches windows. | Private API disables system hotkeys 1 and 2. | Disable Switcher in settings and reopen Tangler, or quit. Restore the prior state; a hotkey already disabled by something else stays disabled. After a force-quit, the next launch restores first (code). |
| ⌘`, ⇧⌘` | Same-app window switching | Tangler's same-app switcher. | Same mechanism, system hotkey 6. | Same as above. |
| ⌃←, ⌃→ | Move one Space left/right | Unchanged by default. Enable Layout → Let Tangler handle desktop shortcuts to run the D [/D ] actions. | System checkboxes remain unchanged; Tangler's earlier event tap consumes keys. Whether it always wins with both enabled is untested. | Disable the toggle. The Open system desktop-shortcut settings action only opens Keyboard settings; the user changes checkboxes. |
| ⌃1 … ⌃9, ⌃0 | Switch to desktop N | Same optional handling as above; ⌃0 selects desktop 10. | Same as above. | Same as above. |
| ⌃↑, ⌃↓, F11 | Mission Control, App Exposé, Show Desktop＊ | Not registered or intercepted; observe Dock notifications only. | Unchanged. | — |
| Right ⌘ | Normal Command modifier | Default leader: hold right Command, then enter a sequence. Captured keys are delivered to Tangler without Command. | While held as leader it is not an ordinary modifier; use left Command for normal shortcuts. | Settings → Shortcuts → Leader key: choose a right-Command tap (still Command when another key is pressed during the tap) or a chord. |
| All keys in leader mode | Input to the focused app | Captured until leader mode ends through Esc or its post-command timeout. | The app does not receive them. | Ends automatically; capture also ends when no consumer is reading, avoiding a stuck keyboard (code). |
| ⌥ + window drag | Native tiling accelerator | Option grid. | Both may resize the window. | Follow the warning and disable the native accelerator in System Settings → Desktop & Dock → Windows. |
| ⌃Space, Caps Lock | Input-source switching on this user's Mac (2026-10-09) | Leave untouched; avoid new bindings on these keys. | Unchanged. | — |

Other software: BetterAndBetter's event tap preceded Tangler's on this Mac and passed keys through unchanged on 2026-10-09.

## System signals and APIs

Public means documented Apple APIs; Accessibility means AX access to other applications, often Dock; private means undocumented functions or fields. Private calls are isolated under module `Private/` directories and detected at startup. Missing capabilities fall back to public mechanisms or report why they are unavailable. Paths below are relative to `Sources/`.

| Signal or API | Kind | Purpose | File | Evidence |
|---|---|---|---|---|
| `CoreDockSendNotification("com.apple.expose.awake", 0)` | Private | Toggle Mission Control. | `WindowKit/Private/DockNotification.swift` | 2026-10-10: 0.1–0.2 s delay; return value ignored. |
| Dock AX tree: `mc` → `mc.display` (`AXDisplayID`) → `mc.spaces` → `mc.spaces.list`, `mc.spaces.add` | Accessibility | Detect Mission Control and read desktop buttons. | `WindowKit/Dock/MissionControlReader.swift` | Exists only while open. Dock responds slowly during animation, so reads use a 1 s timeout. Sibling `mc.windows` has a button per thumbnail; unused in production, inspected during 2026-10-10 debugging. |
| `AXPress` on `mc.spaces.add` | Accessibility | Create a desktop. | `WindowKit/Dock/MissionControlReader.swift`, `WindowKit/Spaces/MissionControl.swift` | 2026-10-10: appeared within 20 ms, 9/9 successes. |
| `AXPress` on a desktop button | Accessibility | Switch to a desktop without a focusable window. | `WindowKit/Spaces/MissionControl.swift` | 2026-10-10: switched about 0.3 s after button readiness following creation. Pressing 50 ms after creation, with a collapsed bar, or after removal in the same session returned success without switching. |
| `AXRemoveDesktop` on a desktop button | Accessibility | Remove a desktop. | `WindowKit/Spaces/MissionControl.swift` | 2026-10-10: appeared in the action list about 0.2 s after creation; succeeded even when absent from the list with a collapsed bar. |
| Dock notifications `AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop`, `AXExposeExit` | Accessibility | Observe overview start/end. | `WindowKit/Dock/ExposeWatcher.swift`, `ExposeObserver.swift` | 2026-10-11: start events 265–277 ms late, exit about 255 ms late. Mission Control has a 1 s polling fallback; the other two modes do not. |
| `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces` | Private | Desktop IDs, UUIDs, type, current state, and display. | `WindowKit/Private/PrivateSpaces.swift`, `WindowKit/Spaces/SpaceParser.swift` | 2026-10-10: numeric IDs last only for the login session, so identity uses UUIDs. UUID stability across reboot is untested. |
| `SLSCopySpacesForWindows` | Private | Window desktop membership, liveness, and desktop occupancy. | `WindowKit/Private/PrivateSpaces.swift`, `WindowKit/Spaces/SpaceOccupancy.swift` | 2026-10-10: closed windows belong to no Space; windows on all Spaces do not count as occupying a particular desktop. |
| `SLSBridgedMoveWindowsToManagedSpaceOperation` | Private | Move windows between desktops. | `WindowKit/Private/SpaceMover.swift`, `WindowKit/Spaces/SpaceMoves.swift` | Available since macOS 26.4 (code); successfully used in workspace reopening on 2026-10-11. |
| Synthetic Dock swipe (`CGEvent`, undocumented fields 55, 110, 123–138, etc.) | Private | Switch adjacent desktops without waiting for animation. | `WindowKit/Private/DockSwipe.swift`, `WindowKit/Spaces/DesktopSwipe.swift` | 2026-10-12: 47 ms/step. Sending does not establish success; each step is checked against the desktop list. |
| `com.apple.swipescrolldirection` preference | Public | Set swipe direction sign. | `WindowKit/Private/DockSwipe.swift` | 2026-10-12 with natural scrolling on: right +1, left −1. Inversion when off is untested. |
| `_AXUIElementGetWindow` | Private | Map AX windows to window-server IDs. | `WindowKit/Private/WindowIdentity.swift` | Code: fallback matches process, position, and title. |
| `_AXUIElementCreateWithRemoteToken` | Private | Find AX-unlisted windows on other desktops. | `WindowKit/Private/RemoteWindowFinder.swift` | Code: budget of 0.1 s per application per attempt. |
| `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `GetProcessForPID` | Private | Raise and focus only the selected window; macOS switches if it is on another desktop. | `WindowKit/Private/PreciseFocus.swift` | 2026-10-10: raised only the selected window. |
| `CGSSetSymbolicHotKeyEnabled`, `CGSIsSymbolicHotKeyEnabled` | Private | Disable/restore system ⌘Tab and ⌘`. | `InputKit/Private/SymbolicHotKeys.swift`, `InputKit/SwitcherHotKeys.swift` | Code; no measurement record. |
| `CGEvent.tapCreate` (session-level, first, event-consuming) | Public | The application's single keyboard/mouse event tap. | `InputKit/SystemEventTap.swift` | Code: macOS disables slow callbacks; Accessibility permission required. |
| `NSWorkspace.activeSpaceDidChangeNotification` | Public | Observe active desktop changes. | `WindowKit/Events/WorkspaceChange.swift` | 2026-10-10: delivered after animation, about 0.55 s late. |
| `NSWorkspace` launch, terminate, hide, unhide, activate, and wake notifications; `NSApplication.didChangeScreenParametersNotification` | Public | Track apps and displays. | `WindowKit/Events/WorkspaceChange.swift` | Code. |
| AX window notifications: creation, destruction, focus, movement, resizing, minimize/restore, title | Accessibility | Track individual windows. | `WindowKit/Events/WindowNotification.swift` | Code. |
| `CGWindowListCopyWindowInfo` | Public | Enumerate window-server windows. | `WindowKit/Inventory/AXInventorySource.swift` | 2026-10-10: includes closed and hidden helper windows, including Safari's 500×500 helper; desktop membership must also be checked. |
| Window `AXDocument` | Accessibility | Capture displayed file/URL for workspace saving. | `WindowKit/Inventory/DocumentURL.swift` | 2026-10-11: Chrome reported URLs; Safari and Finder did not. |
| Application `AXEnhancedUserInterface` | Accessibility | Disable before frame writes, restore afterward. | `WindowKit/Frames/AXFrameBackend.swift`, `FrameApplier.swift` | Code. |
| Application menu bar | Accessibility | Find and invoke the app's New Window action. | `WindowKit/AX/AppMenuReader.swift`, `NewWindowMenu.swift`, `NewWindowOpener.swift` | Code: inspect only the first six menus without showing them. 2026-10-10: invocation worked without activating the app. |
| Dock icons: `AXDockItem`, `AXApplicationDockItem`, `AXIsApplicationRunning` | Accessibility | Identify icons under the pointer and their geometry. | `WindowKit/Dock/DockReader.swift`, `DockGeometry.swift` | Code. |
| Login-session `CGSSessionScreenIsLocked` | Private key in a public function's dictionary | Detect screen lock. | `WindowKit/Private/ScreenLock.swift` | Code: key absent when unlocked. |
| Preferences: `com.apple.dock`/`autohide`; `com.apple.spaces`/`spans-displays`; `com.apple.WindowManager`/`EnableTilingByEdgeDrag`, `EnableTopTilingByEdgeDrag`, `EnableTilingOptionAccelerator` | Public, read-only | Dock autohide, shared/separate display Spaces, native tiling switches. | `DockPreview/DockPreferences.swift`, `WindowKit/Spaces/SeparateSpaces.swift`, `WindowLayout/SystemTiling.swift` | Code: absent tiling keys default to enabled. |
| ScreenCaptureKit: `SCShareableContent`, `SCScreenshotManager`, `SCStream` | Public | Thumbnails and live window content. | `CaptureKit/ScreenCaptureBackend.swift`, `LiveWindowCapture.swift` | Code: reuse thumbnails of the same window for 2 s. |
| `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, `SMAppService.mainApp` | Public | Permissions and launch at login. | `WindowKit/SystemWindowService.swift`, `CaptureKit/ScreenCaptureBackend.swift`, `App/Settings/SettingsModel.swift` | Code. |
| `x-apple.systempreferences:` URLs | Public | Open Accessibility, Screen Recording, and Keyboard settings. | `App/Permissions.swift`, `WindowLayout/LayoutSettingsModel.swift` | Code. |
| SkyLight `SLSBridgedSpace…Operation` classes for creation, switching, destruction | Private | **Not used.** | — | 2026-10-10: class presence only, not exercised. Dock did not recognize desktops made by the older functions they wrap. |

### Tangler overlay window types

Defined in `Sources/OverlayKit/OverlayPanel.swift`; measured on 2026-10-11 with the development probe `Tests/AppTests/LivePanelDesktopProbe.swift`.

| `collectionBehavior` | Used by | Desktop switching | Mission Control |
|---|---|---|---|
| `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]` | Switcher, search, hints, Dock previews, snap previews | Present on every desktop and over full-screen windows (code). | Absent (code). |
| `[.stationary, .ignoresCycle]` | Tab bars | Remain on their desktop. | No thumbnail, but stay visibly floating at their position, so Tangler must hide them. |
| `[.transient, .ignoresCycle]` | No longer used for tab bars | If Tangler is active, switching carries the panel to the new desktop. | Absent; hidden by macOS. |
| `[.managed, .ignoresCycle]` | Unused | Remain on their desktop. | Appear as separate windows. |

- Showing a previously hidden panel on another desktop can move it there. Temporary hiding uses opacity rather than `orderOut` (2026-10-11).
- An ordinary window far outside all displays made Mission Control shrink every thumbnail to 0×0. `.stationary` and `.transient` windows did not (2026-10-10); use those types for real-window tests.
- Mission Control can be inspected without screenshots: read Dock's `mc.windows` while open. Dock logs with `process == "Dock" AND category == "missioncontrol"` recorded entry/exit (2026-10-10).

## Opening windows and content in applications

Tangler uses three paths: without content, invoke the application's New Window menu item through Accessibility; for a file/folder, pass it directly through `NSWorkspace`; for a URL, create a window first and then open the URL. These rules were measured on 2026-10-11 and live in `Sources/WindowKit/AX` and `Sources/Workspaces/Opening`. Menu matching recognizes Chinese new-window titles and “New … Window,” excludes incognito/private/profile/tab actions, and prefers ⌘N.

| Application | New Window menu item | Menu invocation | Opening content | Particular behavior |
|---|---|---|---|---|
| Finder | File → New Finder Window, ⌘N | 2026-10-10: 0.75 s, current desktop, no desktop switch, Finder becomes active. Live test passed on 2026-10-11. | Passing a folder directly creates a window on the current desktop. Creating first produces an extra window (2026-10-11). | Does not report the displayed folder. |
| Safari | File → New Personal Window, ⌘N; title contains the profile name | 2026-10-10: 1.54 s, current desktop, no desktop switch. | Create then open URL: page lands in the new window without an extra window or desktop switch (2026-10-11, user confirmed). Direct URL opening without creation: untested. | Does not report URL; has a hidden 500×500 helper window. |
| Chrome | Not recognized during the 2026-10-10 scan; invoked in the 2026-10-11 test, title not recorded | 2026-10-11: current desktop. | Direct URL opening uses a tab in an existing window and switches to its desktop. Create then open URL uses the new window (2026-10-11). | Reports URL. |
| Terminal | Shell → New Window, a profiles submenu; select its ⌘N item (code) | Untested. | Untested. | Sizes snap to character cells. If the target size is impossible, only Terminal retains a gap; within one cell (24 pt) it can join a tab group (user confirmed 2026-10-12). |
| VS Code | File → New Window, ⇧⌘N | Untested. | Untested. | New windows reposition themselves, which triggered automatic grouping on 2026-10-10. Automatic grouping now recognizes user-initiated moves only. |
| Claude, ChatGPT | Available: New Session in New Window / New Window | Untested. | Untested. | — |
| Sunlogin, Notes | No matching item | — | Untested. | When Sunlogin is frontmost, keys go to the remote computer instead of Tangler (2026-10-09). |
| Tangler itself | — | — | — | 2026-10-10: observed a screen-filling window present on every desktop. Desktop occupancy counts windows belonging only to that desktop. |

If an application already has windows elsewhere, its New Window action still opens on the current desktop for Finder (2026-10-11, `liveNewWindowsStayHereAndFocusCanSwitchDesktops`). Other apps remain untested. A full workspace expansion containing browser URL entries remains untested.
