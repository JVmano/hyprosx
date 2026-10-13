import Foundation

public enum DefaultConfig {
    public static let appsText = """
    # App rules. HyprOSX Settings writes this file; the main config sources it.
    # Example: windowrule = float on, match:class com\\.apple\\.calculator

    """

    public static let text = """
    # HyprOSX config, in Hyprland's format: https://wiki.hypr.land/Configuring/
    # HyprOSX reloads this file when you save it. Errors show in the menu bar and in `hyprctl configerrors`.

    source = ./apps.conf

    $mainMod = ALT
    $terminal = open -na Terminal
    $fileManager = open -a Finder

    general {
        gaps_in = 5
        gaps_out = 20
        border_size = 2
        col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        col.inactive_border = rgba(595959aa)
        layout = dwindle
    }

    decoration {
        rounding = 10
    }

    animations {
        enabled = true
        bezier = easeOutQuint, 0.23, 1, 0.32, 1
        bezier = easeInOutCubic, 0.65, 0.05, 0.36, 1
        bezier = linear, 0, 0, 1, 1
        bezier = almostLinear, 0.5, 0.5, 0.75, 1
        bezier = quick, 0.15, 0, 0.1, 1
        animation = global, 1, 10, default
        animation = border, 1, 5.39, easeOutQuint
        animation = windows, 1, 4.79, easeOutQuint
        animation = windowsIn, 1, 4.1, easeOutQuint, popin 87%
        animation = windowsOut, 1, 1.49, linear, popin 87%
        animation = fadeIn, 1, 1.73, almostLinear
        animation = fadeOut, 1, 1.46, almostLinear
        animation = fade, 1, 3.03, quick
        animation = workspaces, 1, 1.94, almostLinear, fade
        animation = workspacesIn, 1, 1.21, almostLinear, fade
        animation = workspacesOut, 1, 1.94, almostLinear, fade
    }

    dwindle {
        pseudotile = true
        preserve_split = true
    }

    master {
        new_status = master
    }

    bind = $mainMod, Q, exec, $terminal
    bind = $mainMod, C, killactive,
    bind = $mainMod SHIFT, M, exit,
    bind = $mainMod, E, exec, $fileManager
    bind = $mainMod, V, togglefloating,
    bind = $mainMod, P, pseudo,
    bind = $mainMod, J, layoutmsg, togglesplit
    bind = $mainMod, F, fullscreen, 1

    bind = $mainMod, left, movefocus, l
    bind = $mainMod, right, movefocus, r
    bind = $mainMod, up, movefocus, u
    bind = $mainMod, down, movefocus, d

    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod, 6, workspace, 6
    bind = $mainMod, 7, workspace, 7
    bind = $mainMod, 8, workspace, 8
    bind = $mainMod, 9, workspace, 9
    bind = $mainMod, 0, workspace, 10

    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5
    bind = $mainMod SHIFT, 6, movetoworkspace, 6
    bind = $mainMod SHIFT, 7, movetoworkspace, 7
    bind = $mainMod SHIFT, 8, movetoworkspace, 8
    bind = $mainMod SHIFT, 9, movetoworkspace, 9
    bind = $mainMod SHIFT, 0, movetoworkspace, 10

    bind = $mainMod, S, togglespecialworkspace, magic
    bind = $mainMod SHIFT, S, movetoworkspace, special:magic

    """
}
