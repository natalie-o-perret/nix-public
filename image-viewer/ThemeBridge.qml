import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string cache: Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"
    readonly property string config: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    property var palette: ({})
    property var typography: ({})
    property var settings: ({})

    readonly property var tokens: {
        const mode = palette.mode === "light" ? "light" : "dark";
        const colors = palette.colors?.[mode] || {};
        const result = Object.assign({}, typography, {
            isLightMode: mode === "light",
            radiusStrength: settings.radiusStrength ?? 50,
            shapeMorph: settings.interfaceStyle !== "classic",
            pillControls: settings.interfaceStyle !== "classic"
        });
        for (const name in colors)
            result[name.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())] = colors[name];
        if (colors.on_primary)
            result.primaryText = colors.on_primary;
        if (colors.on_surface)
            result.surfaceText = colors.on_surface;
        if (colors.on_surface_variant)
            result.surfaceVariantText = colors.on_surface_variant;
        const scale = typography.fontScale || 1;
        for (const [name, size] of Object.entries({Small: 12, Medium: 14, Large: 16, XLarge: 20, XXLarge: 28}))
            result["fontSize" + name] = size * scale;
        return result;
    }

    function parse(view, previous) {
        try {
            const value = JSON.parse(view.text());
            return value && typeof value === "object" && !Array.isArray(value) ? value : previous;
        } catch (error) {
            console.warn("Keeping the last valid DMS theme:", error.message);
            return previous;
        }
    }

    FileView {
        id: colors
        path: root.cache + "/dms/dms-colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.palette = root.parse(colors, root.palette)
    }
    FileView {
        id: fonts
        path: root.cache + "/dms/dms-typography.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.typography = root.parse(fonts, root.typography)
    }
    FileView {
        id: preferences
        path: root.config + "/dms/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.settings = root.parse(preferences, root.settings)
    }
}
