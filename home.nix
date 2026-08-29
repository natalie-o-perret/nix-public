{
  browserPolicies,
  config,
  lib,
  managedBookmarks,
  pkgs,
  ...
}:

let
  niriConfig =
    pkgs.runCommand "niri-config.kdl"
      {
        nativeBuildInputs = [ pkgs.niri ];
      }
      ''
        niri validate --config ${./niri.kdl}
        cp ${./niri.kdl} $out
      '';

  bibataIce = pkgs.runCommand "bibata-modern-ice" { } ''
    mkdir -p $out/share/icons
    cp -r ${pkgs.bibata-cursors}/share/icons/Bibata-Modern-Ice $out/share/icons/
  '';

  papirusPink = pkgs.papirus-icon-theme.override {
    color = "pink";
  };

  qt6ctKde = pkgs.qt6Packages.qt6ct.overrideAttrs (old: {
    pname = "qt6ct-kde";
    patches = (old.patches or [ ]) ++ [
      (pkgs.fetchpatch {
        url = "https://aur.archlinux.org/cgit/aur.git/plain/qt6ct-shenanigans.patch?h=qt6ct-kde&id=8c1003e13b7e7545e717273e0716f095f195bd13";
        hash = "sha256-Q8QOMDy84z6FD0OkSLylEwB+/Zs50jcUgR+4J6Lmwmk=";
      })
    ];
    buildInputs =
      (old.buildInputs or [ ])
      ++ (with pkgs.kdePackages; [
        kconfig
        kcolorscheme
        kiconthemes
      ]);
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.kdePackages.extra-cmake-modules ];
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      "-DKF6Config_DIR=${pkgs.kdePackages.kconfig}/lib/cmake/KF6Config"
      "-DKF6ColorScheme_DIR=${pkgs.kdePackages.kcolorscheme}/lib/cmake/KF6ColorScheme"
      "-DKF6IconThemes_DIR=${pkgs.kdePackages.kiconthemes}/lib/cmake/KF6IconThemes"
    ];
  });

  desktopScale = 1.25;
  desktopFont = {
    name = "Inter Variable";
    size = builtins.ceil (10 * desktopScale);
  };

  browserScale = {
    vivaldi = 1.2;
    helium = 1.3;
  };

  scaledVlc = pkgs.symlinkJoin {
    name = "vlc-scaled";
    paths = [ pkgs.vlc ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/vlc"
      makeWrapper ${pkgs.vlc}/bin/vlc "$out/bin/vlc" \
        --set QT_SCALE_FACTOR 1.6 \
        --set QT_FONT_DPI 60

      desktop="$out/share/applications/vlc.desktop"
      rm "$desktop"
      cp ${pkgs.vlc}/share/applications/vlc.desktop "$desktop"
      substituteInPlace "$desktop" \
        --replace-fail "Exec=${pkgs.vlc}/bin/vlc" "Exec=$out/bin/vlc"
    '';
    meta = pkgs.vlc.meta // { outputsToInstall = [ "out" ]; };
  };

  dmsVivaldi =
    (pkgs.vivaldi.override {
      proprietaryCodecs = true;
      enableWidevine = true;
      commandLineArgs = "--force-device-scale-factor=${toString browserScale.vivaldi}";
    }).overrideAttrs (old: {
      postFixup = (old.postFixup or "") + ''
        prefs="$out/opt/vivaldi/resources/vivaldi/prefs_definitions.json"
        ${pkgs.jq}/bin/jq '
          .vivaldi.theme.schedule.enabled.default = "off"
          | .vivaldi.themes.current.default = "Vivaldi2"
          | .vivaldi.themes.current_private.default = "Vivaldi2"
          | (.vivaldi.themes.system.default[] | select(.id == "Vivaldi2")) |= (
              .name = "DMS Pink"
              | .accentFromPage = false
              | .backgroundImage = ""
              | .blur = 0
              | .colorAccentBg = "#e91e63"
              | .colorBg = "#191112"
              | .colorFg = "#f0dee0"
              | .colorHighlightBg = "#e91e63"
              | .colorWindowBg = "#261d1e"
            )
        ' "$prefs" > "$prefs.tmp"
        mv "$prefs.tmp" "$prefs"
      '';
    });

  compactDms = pkgs.dms-shell.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      qml="$out/share/quickshell/dms/Modals/Clipboard/ClipboardConstants.qml"
      chmod u+w "$qml"
      substituteInPlace "$qml" \
        --replace-fail 'readonly property int modalWidth: 650' 'readonly property int modalWidth: 520' \
        --replace-fail 'readonly property int modalHeight: 550' 'readonly property int modalHeight: 440' \
        --replace-fail 'readonly property int popoutWidth: 550' 'readonly property int popoutWidth: 440' \
        --replace-fail 'readonly property int popoutHeight: 500' 'readonly property int popoutHeight: 400' \
        --replace-fail 'readonly property int itemHeight: 72' 'readonly property int itemHeight: 64' \
        --replace-fail 'readonly property int thumbnailSize: 100' 'readonly property int thumbnailSize: 88' \
        --replace-fail 'readonly property int keyboardHintsHeight: 80' 'readonly property int keyboardHintsHeight: 64'
    '';
  });

  dmsSystemAppTheming = pkgs.writeShellApplication {
    name = "dms-system-app-theming";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
    ];
    text = ''
      shell_dir=${compactDms}/share/quickshell/dms
      for _ in {1..100}; do
        if [[ -f "$HOME/.config/gtk-3.0/dank-colors.css" && -f "$HOME/.local/share/color-schemes/DankMatugen.colors" ]]; then
          "$shell_dir/scripts/gtk.sh" "$HOME/.config" false "$shell_dir"
          "$shell_dir/scripts/qt.sh" "$HOME/.config"
          exit 0
        fi
        sleep 0.1
      done
      echo "DMS theme files were not generated" >&2
      exit 1
    '';
  };

  emojiLauncher = pkgs.fetchFromGitHub {
    owner = "devnullvoid";
    repo = "dms-emoji-launcher";
    rev = "8ff394e3ddfcb2fd755ed2e7b4c6f01f3e26e596";
    hash = "sha256-fmIddCvACwO8wbAtLBMtDnEXXQJjb7+o2s4jW3f8VIU=";
  };

  qtAppearance = {
    icon_theme = "Papirus-Dark";
    standard_dialogs = "xdgdesktopportal";
    style = "Fusion";
  };

  qtFonts.general = ''"${desktopFont.name},${toString desktopFont.size},-1,5,50,0,0,0,0,0"'';

  # DMS has no declarative settings option; enforce desktop integration before it starts.
  dmsDesktopSettings = pkgs.writeShellScript "dms-desktop-settings" ''
    set -eu
    settings="$HOME/.config/DankMaterialShell/settings.json"
    [[ -f "$settings" ]] || exit 0
    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    ${pkgs.jq}/bin/jq '
      .iconThemeDark = "Papirus-Dark"
      | .iconThemeLight = "Papirus-Dark"
      | .iconThemePerMode = false
      | .lastAppliedIconTheme = "Papirus-Dark"
      | .fontFamily = "${desktopFont.name}"
      | .fontScale = 1.0
      | .cursorSettings.theme = "Bibata-Modern-Ice"
      | .cursorSettings.size = 24
      | .gtkThemingEnabled = true
      | .qtThemingEnabled = true
      | .runDmsMatugenTemplates = true
      | .matugenTemplateGtk = true
      | .matugenTemplateNiri = true
      | .matugenTemplateQt5ct = true
      | .matugenTemplateQt6ct = true
      | .matugenTemplateFirefox = false
      | .matugenTemplateZenBrowser = true
      | .matugenTemplateZed = true
      | .syncModeWithPortal = true
      | .showBatteryPercent = true
      | .showBatteryPercentOnlyOnBattery = false
      | ((.barConfigs[] | select(.id == "default")) |= (
          .innerPadding = 11
          | .fontScale = 1.2
          | .iconScale = 1.2
          | .rightWidgets |= map(select((if type == "string" then . else .id end) != "exampleEmojiPlugin"))
        ))
    ' "$settings" > "$tmp"
    ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$settings"
  '';

  heliumPolicies = builtins.toJSON (browserPolicies // { ManagedBookmarks = managedBookmarks; });

  # ponytail: Helium is not in nixpkgs; bump this pinned release when updating.
  helium =
    let
      pname = "helium";
      version = "0.16.1.1";
      src = pkgs.fetchurl {
        url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
        hash = "sha256-KZFPd7RdwbDQ/hDXgV4bZKytO+4dtyig7ctDzIj20ng=";
      };
      contents = pkgs.appimageTools.extract { inherit pname version src; };
    in
    pkgs.appimageTools.wrapType2 {
      inherit pname version src;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      extraPkgs = _: [
        (pkgs.writeTextDir "etc/chromium/policies/managed/browser.json" heliumPolicies)
      ];
      extraInstallCommands = ''
        wrapProgram "$out/bin/helium" \
          --add-flags "--force-device-scale-factor=${toString browserScale.helium}"
        install -Dm444 ${contents}/helium.desktop $out/share/applications/helium.desktop
        cp -r ${contents}/usr/share/icons $out/share
      '';
    };
in
{
  home.stateVersion = "26.05";
  home.sessionVariables.QT_QPA_PLATFORMTHEME_QT6 = "qt6ct";
  systemd.user.sessionVariables.QT_QPA_PLATFORMTHEME_QT6 = "qt6ct";
  xdg.enable = true;

  systemd.user.tmpfiles.rules = [
    "d %h/Personal 0755 - - -"
    "d %h/Personal/Repositories 0755 - - -"
  ];

  home.packages = with pkgs; [
    audacity
    btop
    cargo
    clippy
    discord
    fastfetch
    fira-code
    gh
    gimp
    go
    helium
    inter
    jetbrains-toolbox
    karere
    lsd
    papirusPink
    pear-desktop
    pdfarranger
    python3
    qbittorrent
    rustc
    rustfmt
    signal-desktop
    spotify
    swappy
    telegram-desktop
    dmsVivaldi
    scaledVlc
    wl-clipboard
    xwayland-satellite
    yazi
    zig
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts.sansSerif = [ desktopFont.name ];
  };

  home.pointerCursor = {
    enable = true;
    package = bibataIce;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
  };

  gtk = {
    enable = true;
    colorScheme = "dark";
    gtk2.enable = false;
    gtk3.bookmarks = [
      "file://${config.home.homeDirectory}/Personal Personal"
      "file://${config.home.homeDirectory}/Professional Professional"
    ];
    font = {
      inherit (desktopFont) name size;
      package = pkgs.inter;
    };
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = papirusPink;
    };
    gtk3.extraConfig.gtk-xft-dpi = 147456;
    gtk4.extraConfig.gtk-xft-dpi = 147456;
  };

  qt = {
    enable = true;
    platformTheme = {
      name = "qtct";
      package = [
        pkgs.libsForQt5.qt5ct
        qt6ctKde
      ];
    };
    qt5ctSettings = {
      Appearance = qtAppearance;
      Fonts = qtFonts;
    };
    qt6ctSettings = {
      Appearance = qtAppearance;
      Fonts = qtFonts;
    };
  };

  xfconf.settings.thunar = {
    "last-location-bar" = "ThunarLocationButtons";
    "misc-single-click" = true;
    "misc-single-click-timeout" = 1;
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      if [[ ''${TERM_PROGRAM:-} == ghostty && -z ''${FASTFETCH_DISPLAYED:-} ]]; then
        export FASTFETCH_DISPLAYED=1
        fastfetch
      fi
    '';
  };

  programs.git = {
    enable = true;
    settings.user = {
      name = "Natalie Perret";
      email = "11332444+natalie-o-perret@users.noreply.github.com";
    };
  };

  programs.ghostty = {
    enable = true;
    settings.theme = "dankcolors";
  };

  programs.zen-browser = {
    enable = true;
    policies = lib.mkForce {
      ExtensionSettings."authenticator@mymindstorm" = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/auth-helper/latest.xpi";
        installation_mode = "force_installed";
      };
      Homepage = {
        URL = "about:blank";
        Locked = true;
        StartPage = "homepage-locked";
      };
      ManagedBookmarks = managedBookmarks;
      NewTabPage = false;
      SearchEngines.Default = "Google";
      VisualSearchEnabled = true;
      Preferences = {
        "general.autoScroll" = {
          Value = true;
          Status = "locked";
        };
        "toolkit.legacyUserProfileCustomizations.stylesheets" = {
          Value = true;
          Status = "locked";
        };
      };
    };
  };

  programs.zed-editor = {
    enable = true;
    defaultEditor = true;
    userSettings = {
      ui_font_family = desktopFont.name;
      ui_font_size = builtins.ceil (16 * desktopScale);
      buffer_font_family = "Fira Code";
      buffer_font_size = builtins.ceil (15 * desktopScale);
      theme = {
        mode = "system";
        light = "DankShell Light";
        dark = "DankShell Dark";
      };
    };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "thunar.desktop" ];
      "text/plain" = [ "dev.zed.Zed.desktop" ];
    };
  };

  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "com.mitchellh.ghostty.desktop" ];
  };

  programs.dank-material-shell = {
    enable = true;
    package = compactDms;
    dgop.package = pkgs.dgop;
    managePluginSettings = true;
    plugins.emojiLauncher = {
      enable = true;
      src = emojiLauncher;
    };
    quickshell.package = pkgs.quickshell;
    systemd = {
      enable = true;
      target = "niri.service";
    };
  };

  systemd.user.services.dms.Service = {
    Environment = [
      "XCURSOR_THEME=Bibata-Modern-Ice"
      "XCURSOR_SIZE=24"
    ];
    ExecStartPre = [ dmsDesktopSettings ];
    ExecStartPost = [ "${dmsSystemAppTheming}/bin/dms-system-app-theming" ];
  };

  programs.opencode.enable = true;

  dconf.settings."io/github/tobagin/karere".theme = "system";

  home.activation.signalSystemTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.config/Signal/ephemeral.json"
    [[ -f "$settings" ]] || exit 0
    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    ${pkgs.jq}/bin/jq '."theme-setting" = "system"' "$settings" > "$tmp"
    ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$settings"
  '';

  xdg.configFile = {
    "gtk-3.0/settings.ini".force = true;
    "gtk-4.0/settings.ini".force = true;
    "niri/config.kdl".source = niriConfig;
    "qt5ct/qt5ct.conf".force = true;
    "qt6ct/qt6ct.conf".force = true;
    "zen/smo9aotg.Default Profile/chrome/userChrome.css" = {
      force = true;
      text = ''@import url("file://${config.xdg.configHome}/DankMaterialShell/zen.css");'';
    };

    "opencode/opencode.jsonc" = {
      force = true;
      text = ''
        // Managed by Home Manager.
        {
          "$schema": "https://opencode.ai/config.json",
          "plugin": ["@dietrichgebert/ponytail@4.9.0"]
        }
      '';
    };

    "opencode/tui.json" = {
      force = true;
      text = ''
        {
          "$schema": "https://opencode.ai/tui.json",
          "theme": "system"
        }
      '';
    };
  };
}
