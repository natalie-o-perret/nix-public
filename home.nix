{
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

  matchaPink =
    (pkgs.matcha-gtk-theme.override {
      colorVariants = [ "dark" ];
      themeVariants = [ "aliz" ];
    }).overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/gtk/gtk-{3.0,4.0}/gtk-dark-aliz.css \
          --replace-fail '#F0544C' '#E91F7A' \
          --replace-fail '240, 84, 76' '233, 31, 122'
      '';
    });

  desktopFont = {
    name = "Inter Variable";
    size = 10;
  };

  qtAppearance = {
    custom_palette = true;
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
      | .cursorSettings.theme = "Bibata-Modern-Ice"
      | .cursorSettings.size = 24
      | .qtThemingEnabled = true
      | .showBatteryPercent = true
      | .showBatteryPercentOnlyOnBattery = false
      | ((.barConfigs[] | select(.id == "default")) |= (
          .innerPadding = 8
          | .fontScale = 1.1
          | .iconScale = 1.1
          | .rightWidgets |= (
              if any(.[]; ((if type == "string" then . else .id end) == "exampleEmojiPlugin"))
              then .
              else . + [{"id": "exampleEmojiPlugin", "enabled": true}]
              end
            )
        ))
    ' "$settings" > "$tmp"
    ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$settings"
  '';

  managedBookmarksPolicy = builtins.toJSON { ManagedBookmarks = managedBookmarks; };

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
      extraPkgs = _: [
        (pkgs.writeTextDir "etc/chromium/policies/managed/bookmarks.json" managedBookmarksPolicy)
      ];
      extraInstallCommands = ''
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
    kdePackages.kate
    lsd
    matchaPink
    papirusPink
    pear-desktop
    pdfarranger
    python3
    rustc
    rustfmt
    signal-desktop
    spotify
    swappy
    telegram-desktop
    (vivaldi.override {
      proprietaryCodecs = true;
      enableWidevine = true;
    })
    vlc
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
    font = {
      inherit (desktopFont) name size;
      package = pkgs.inter;
    };
    theme = {
      name = "Matcha-dark-aliz";
      package = matchaPink;
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
    platformTheme.name = "qtct";
    qt5ctSettings = {
      Appearance = qtAppearance // {
        color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/matugen.conf";
      };
      Fonts = qtFonts;
    };
    qt6ctSettings = {
      Appearance = qtAppearance // {
        color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/matugen.conf";
      };
      Fonts = qtFonts;
    };
  };

  xfconf.settings.thunar = {
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
      ManagedBookmarks = managedBookmarks;
    };
  };

  programs.zed-editor = {
    enable = true;
    defaultEditor = true;
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
    package = pkgs.dms-shell;
    dgop.package = pkgs.dgop;
    managePluginSettings = true;
    plugins.exampleEmojiPlugin = {
      enable = true;
      src = "${pkgs.dms-shell}/share/quickshell/dms/PLUGINS/ExampleEmojiPlugin";
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
  };

  programs.opencode.enable = true;

  xdg.configFile = {
    "gtk-3.0/settings.ini".force = true;
    "gtk-4.0/settings.ini".force = true;
    "niri/config.kdl".source = niriConfig;
    "qt5ct/qt5ct.conf".force = true;
    "qt6ct/qt6ct.conf".force = true;

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
