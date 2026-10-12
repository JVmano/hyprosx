import Foundation

public struct GeneralOptions: Equatable, Sendable {
    public var borderSize = 1
    public var gapsIn = Edges(all: 5)
    public var gapsOut = Edges(all: 20)
    public var floatGaps = Edges(all: 0)
    public var gapsWorkspaces = 0
    public var activeBorder = Gradient(Color(r: 1, g: 1, b: 1, a: 1))
    public var inactiveBorder = Gradient(Color(r: 68.0 / 255, g: 68.0 / 255, b: 68.0 / 255, a: 1))
    public var layout = "dwindle"
    public var noFocusFallback = false
    public init() {}
}

public struct DecorationOptions: Equatable, Sendable {
    public var rounding = 0
    public var dimInactive = false
    public var dimStrength = 0.5
    public init() {}
}

public struct AnimationsOptions: Equatable, Sendable {
    public var enabled = true
    public var workspaceWraparound = false
    public init() {}
}

public struct InputOptions: Equatable, Sendable {
    public var followMouse = 1
    public var focusOnClose = 0
    public init() {}
}

public struct BindsOptions: Equatable, Sendable {
    public var workspaceBackAndForth = false
    public var allowWorkspaceCycles = false
    public var focusPreferredMethod = 0
    public var movefocusCyclesFullscreen = false
    public var windowDirectionMonitorFallback = true
    public var dragThreshold = 0
    public var scrollEventDelay = 300
    public var hideSpecialOnWorkspaceChange = false
    public init() {}
}

public struct CursorOptions: Equatable, Sendable {
    public var noWarps = false
    public var warpOnChangeWorkspace = 0
    public init() {}
}

public struct MiscOptions: Equatable, Sendable {
    public var disableAutoreload = false
    public var focusOnActivate = true
    public var closeSpecialOnEmpty = true
    public var animateManualResizes = false
    public var animateMouseWindowdragging = false
    public var sizeLimitsTiled = false
    public init() {}
}

public struct DwindleOptions: Equatable, Sendable {
    public var pseudotile = false
    public var forceSplit = 0
    public var preserveSplit = false
    public var smartSplit = false
    public var smartResizing = true
    public var permanentDirectionOverride = false
    public var specialScaleFactor = 1.0
    public var splitWidthMultiplier = 1.0
    public var useActiveForSplits = true
    public var defaultSplitRatio = 1.0
    public var splitBias = 0
    public var preciseMouseMove = false
    public init() {}
}

public struct MasterOptions: Equatable, Sendable {
    public var allowSmallSplit = false
    public var specialScaleFactor = 1.0
    public var mfact = 0.55
    public var newStatus = "slave"
    public var newOnTop = false
    public var newOnActive = "none"
    public var orientation = "left"
    public var slaveCountForCenterMaster = 2
    public var centerMasterFallback = "left"
    public var smartResizing = true
    public var dropAtCursor = true
    public var alwaysKeepPosition = false
    public var focusMasterOnClose = false
    public init() {}
}

public struct MacOSOptions: Equatable, Sendable {
    public var unhideHiddenApps = false
    public var hideParkedApps = true
    public var animationsOnLowPower = false
    public var respectReduceMotion = true
    public var liveResizeMaxLatency = 6.0
    public var borderRadius = -1
    public var ipcExec = false
    public var ipcWindowTitles = true
    public init() {}
}

struct OptionSpec {
    let set: (inout Config, String) -> String?
    let get: (Config) -> String
}

enum OptionRegistry {
    static func integerText(_ d: Double) -> String {
        Int(exactly: d.rounded()).map(String.init) ?? String(d)
    }

    static func hexByte(_ unit: Double) -> String {
        let n = unit.isFinite ? Int(min(max((unit * 255).rounded(), 0), 255)) : 0
        return (n < 16 ? "0" : "") + String(n, radix: 16)
    }

    static let specs: [String: OptionSpec] = {
        var s: [String: OptionSpec] = [:]
        func invalid(_ v: String, _ k: String) -> String { "invalid value '\(v)' for \(k)" }
        func int(_ k: String, _ p: WritableKeyPath<Config, Int>) {
            s[k] = OptionSpec(set: { c, v in guard let n = ConfigValue.int(v) else { return invalid(v, k) }; c[keyPath: p] = n; return nil },
                              get: { "\($0[keyPath: p])" })
        }
        func bool(_ k: String, _ p: WritableKeyPath<Config, Bool>) {
            s[k] = OptionSpec(set: { c, v in guard let b = ConfigValue.bool(v) else { return invalid(v, k) }; c[keyPath: p] = b; return nil },
                              get: { $0[keyPath: p] ? "true" : "false" })
        }
        func strictBool(_ k: String, _ p: WritableKeyPath<Config, Bool>) {
            s[k] = OptionSpec(set: { c, v in
                switch v.trimmingCharacters(in: .whitespaces).lowercased() {
                case "true", "yes", "on", "1": c[keyPath: p] = true
                case "false", "no", "off", "0": c[keyPath: p] = false
                default: return invalid(v, k)
                }
                return nil
            }, get: { $0[keyPath: p] ? "true" : "false" })
        }
        func float(_ k: String, _ p: WritableKeyPath<Config, Double>) {
            s[k] = OptionSpec(set: { c, v in guard let d = ConfigValue.float(v) else { return invalid(v, k) }; c[keyPath: p] = d; return nil },
                              get: { String($0[keyPath: p]) })
        }
        func edges(_ k: String, _ p: WritableKeyPath<Config, Edges>) {
            s[k] = OptionSpec(set: { c, v in guard let e = ConfigValue.edges(v) else { return invalid(v, k) }; c[keyPath: p] = e; return nil },
                              get: { let e = $0[keyPath: p]; return [e.top, e.right, e.bottom, e.left].map(OptionRegistry.integerText).joined(separator: " ") })
        }
        func gradient(_ k: String, _ p: WritableKeyPath<Config, Gradient>) {
            s[k] = OptionSpec(set: { c, v in guard let g = ConfigValue.gradient(v) else { return invalid(v, k) }; c[keyPath: p] = g; return nil },
                              get: { c in
                                  let g = c[keyPath: p]
                                  return g.colors.map { "rgba(\(hexByte($0.r))\(hexByte($0.g))\(hexByte($0.b))\(hexByte($0.a)))" }.joined(separator: " ")
                                      + " \(integerText(g.angleDegrees))deg"
                              })
        }
        func choice(_ k: String, _ p: WritableKeyPath<Config, String>, _ allowed: [String]) {
            s[k] = OptionSpec(set: { c, v in guard allowed.contains(v) else { return invalid(v, k) }; c[keyPath: p] = v; return nil },
                              get: { $0[keyPath: p] })
        }
        int("general:border_size", \.general.borderSize)
        edges("general:gaps_in", \.general.gapsIn)
        edges("general:gaps_out", \.general.gapsOut)
        edges("general:float_gaps", \.general.floatGaps)
        int("general:gaps_workspaces", \.general.gapsWorkspaces)
        gradient("general:col.active_border", \.general.activeBorder)
        gradient("general:col.inactive_border", \.general.inactiveBorder)
        s["general:layout"] = OptionSpec(set: { c, v in
            if v == "scrolling" { return "layout scrolling is not supported by HyprOSX" }
            guard ["dwindle", "master", "monocle"].contains(v) else { return invalid(v, "general:layout") }
            c.general.layout = v; return nil
        }, get: { $0.general.layout })
        bool("general:no_focus_fallback", \.general.noFocusFallback)
        int("decoration:rounding", \.decoration.rounding)
        bool("decoration:dim_inactive", \.decoration.dimInactive)
        float("decoration:dim_strength", \.decoration.dimStrength)
        bool("animations:enabled", \.animationsOptions.enabled)
        bool("animations:workspace_wraparound", \.animationsOptions.workspaceWraparound)
        int("input:follow_mouse", \.input.followMouse)
        int("input:focus_on_close", \.input.focusOnClose)
        bool("binds:workspace_back_and_forth", \.bindsOptions.workspaceBackAndForth)
        bool("binds:allow_workspace_cycles", \.bindsOptions.allowWorkspaceCycles)
        int("binds:focus_preferred_method", \.bindsOptions.focusPreferredMethod)
        bool("binds:movefocus_cycles_fullscreen", \.bindsOptions.movefocusCyclesFullscreen)
        bool("binds:window_direction_monitor_fallback", \.bindsOptions.windowDirectionMonitorFallback)
        int("binds:drag_threshold", \.bindsOptions.dragThreshold)
        int("binds:scroll_event_delay", \.bindsOptions.scrollEventDelay)
        bool("binds:hide_special_on_workspace_change", \.bindsOptions.hideSpecialOnWorkspaceChange)
        bool("cursor:no_warps", \.cursor.noWarps)
        int("cursor:warp_on_change_workspace", \.cursor.warpOnChangeWorkspace)
        bool("misc:disable_autoreload", \.misc.disableAutoreload)
        bool("misc:focus_on_activate", \.misc.focusOnActivate)
        bool("misc:close_special_on_empty", \.misc.closeSpecialOnEmpty)
        bool("misc:animate_manual_resizes", \.misc.animateManualResizes)
        bool("misc:animate_mouse_windowdragging", \.misc.animateMouseWindowdragging)
        bool("misc:size_limits_tiled", \.misc.sizeLimitsTiled)
        bool("dwindle:pseudotile", \.dwindle.pseudotile)
        int("dwindle:force_split", \.dwindle.forceSplit)
        bool("dwindle:preserve_split", \.dwindle.preserveSplit)
        bool("dwindle:smart_split", \.dwindle.smartSplit)
        bool("dwindle:smart_resizing", \.dwindle.smartResizing)
        bool("dwindle:permanent_direction_override", \.dwindle.permanentDirectionOverride)
        float("dwindle:special_scale_factor", \.dwindle.specialScaleFactor)
        float("dwindle:split_width_multiplier", \.dwindle.splitWidthMultiplier)
        bool("dwindle:use_active_for_splits", \.dwindle.useActiveForSplits)
        float("dwindle:default_split_ratio", \.dwindle.defaultSplitRatio)
        int("dwindle:split_bias", \.dwindle.splitBias)
        bool("dwindle:precise_mouse_move", \.dwindle.preciseMouseMove)
        bool("master:allow_small_split", \.master.allowSmallSplit)
        float("master:special_scale_factor", \.master.specialScaleFactor)
        float("master:mfact", \.master.mfact)
        choice("master:new_status", \.master.newStatus, ["master", "slave", "inherit"])
        bool("master:new_on_top", \.master.newOnTop)
        choice("master:new_on_active", \.master.newOnActive, ["none", "before", "after"])
        choice("master:orientation", \.master.orientation, ["left", "right", "top", "bottom", "center"])
        int("master:slave_count_for_center_master", \.master.slaveCountForCenterMaster)
        choice("master:center_master_fallback", \.master.centerMasterFallback, ["left", "right", "top", "bottom"])
        bool("master:smart_resizing", \.master.smartResizing)
        bool("master:drop_at_cursor", \.master.dropAtCursor)
        bool("master:always_keep_position", \.master.alwaysKeepPosition)
        bool("master:focus_master_on_close", \.master.focusMasterOnClose)
        bool("macos:unhide_hidden_apps", \.macos.unhideHiddenApps)
        bool("macos:hide_parked_apps", \.macos.hideParkedApps)
        bool("macos:animations_on_low_power", \.macos.animationsOnLowPower)
        bool("macos:respect_reduce_motion", \.macos.respectReduceMotion)
        float("macos:live_resize_max_latency", \.macos.liveResizeMaxLatency)
        int("macos:border_radius", \.macos.borderRadius)
        strictBool("macos:ipc_exec", \.macos.ipcExec)
        bool("macos:ipc_window_titles", \.macos.ipcWindowTitles)
        return s
    }()

    static let ignoredExact: Set<String> = [
        "general:col.nogroup_border", "general:col.nogroup_border_active", "general:resize_on_border",
        "general:extend_border_grab_area", "general:hover_icon_on_border", "general:allow_tearing", "general:resize_corner",
        "general:modal_parent_blocking", "general:locale",
        "decoration:rounding_power", "decoration:active_opacity", "decoration:inactive_opacity", "decoration:fullscreen_opacity",
        "decoration:dim_modal", "decoration:dim_special", "decoration:dim_around", "decoration:screen_shader",
        "decoration:border_part_of_window",
        "input:kb_model", "input:kb_layout", "input:kb_variant", "input:kb_options", "input:kb_rules", "input:kb_file",
        "input:numlock_by_default", "input:resolve_binds_by_sym", "input:repeat_rate", "input:repeat_delay", "input:sensitivity",
        "input:accel_profile", "input:force_no_accel", "input:rotation", "input:left_handed", "input:scroll_points",
        "input:scroll_method", "input:scroll_button", "input:scroll_button_lock", "input:scroll_factor", "input:natural_scroll",
        "input:follow_mouse_shrink", "input:follow_mouse_threshold", "input:mouse_refocus", "input:float_switch_override_focus",
        "input:special_fallthrough", "input:off_window_axis_events", "input:emulate_discrete_scroll",
        "binds:pass_mouse_when_bound", "binds:workspace_center_on", "binds:ignore_group_lock", "binds:movefocus_cycles_groupfirst",
        "binds:disable_keybind_grabbing", "binds:allow_pin_fullscreen",
        "cursor:invisible", "cursor:sync_gsettings_theme", "cursor:no_hardware_cursors", "cursor:no_break_fs_vrr",
        "cursor:min_refresh_rate", "cursor:hotspot_padding", "cursor:inactive_timeout", "cursor:persistent_warps",
        "cursor:warp_on_toggle_special", "cursor:default_monitor", "cursor:zoom_factor", "cursor:zoom_rigid",
        "cursor:zoom_detached_camera", "cursor:enable_hyprcursor", "cursor:hide_on_key_press", "cursor:hide_on_touch",
        "cursor:hide_on_tablet", "cursor:use_cpu_buffer", "cursor:warp_back_after_non_mouse_input", "cursor:zoom_disable_aa",
        "misc:disable_hyprland_logo", "misc:disable_splash_rendering", "misc:disable_scale_notification", "misc:col.splash",
        "misc:font_family", "misc:splash_font_family", "misc:force_default_wallpaper", "misc:vrr", "misc:mouse_move_enables_dpms",
        "misc:key_press_enables_dpms", "misc:name_vk_after_proc", "misc:always_follow_on_dnd", "misc:layers_hog_keyboard_focus",
        "misc:enable_swallow", "misc:swallow_regex", "misc:swallow_exception_regex", "misc:mouse_move_focuses_monitor",
        "misc:allow_session_lock_restore", "misc:session_lock_xray", "misc:background_color", "misc:on_focus_under_fullscreen",
        "misc:exit_window_retains_fullscreen", "misc:initial_workspace_tracking", "misc:middle_click_paste",
        "misc:render_unfocused_fps", "misc:disable_xdg_env_checks", "misc:disable_hyprland_qtutils_check",
        "misc:disable_hyprland_guiutils_check", "misc:lockdead_screen_delay", "misc:enable_anr_dialog", "misc:anr_missed_pings",
        "misc:disable_watchdog_warning", "misc:vfr", "misc:screencopy_force_8b", "misc:new_window_takes_over_fullscreen",
        "dwindle:single_window_aspect_ratio", "dwindle:single_window_aspect_ratio_tolerance", "master:center_ignores_reserved",
    ]

    static let ignoredPrefixes = [
        "general:snap:", "decoration:blur:", "decoration:shadow:", "decoration:glow:", "input:touchpad:", "input:touchdevice:",
        "input:tablet:", "input:virtualkeyboard:", "group:", "debug:", "render:", "opengl:", "ecosystem:", "xwayland:",
        "experimental:", "gestures:", "quirks:", "layout:", "plugin:", "device:", "monitorv2:", "scrolling:",
    ]

    static func isIgnored(_ key: String) -> Bool {
        ignoredExact.contains(key) || ignoredPrefixes.contains { key.hasPrefix($0) }
    }
}
