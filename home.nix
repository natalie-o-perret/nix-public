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

  desktopScale = 1.25;
  desktopFont = {
    name = "Inter Variable";
    size = builtins.ceil (10 * desktopScale);
  };

  browserScale = {
    vivaldi = 1.25;
    helium = 1.2;
  };

  qt5MenuStyle = pkgs.writeText "qt5-menu.qss" "QMenuBar, QMenu { font-size: 14px; }\n";

  logseq =
    # ponytail: Logseq 0.10.15 fails with Electron 43; retry the current Electron after upgrading Logseq.
    (pkgs.logseq.override { electron_39 = pkgs.electron_41; }).overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/main/frontend/state.cljs \
          --replace-fail '(or (storage/get :ui/theme) "light")' '(or (storage/get :ui/theme) "dark")' \
          --replace-fail '((fnil identity (or util/mac? util/win32? false)) (storage/get :ui/system-theme?))' '((fnil identity true) (storage/get :ui/system-theme?))' \
          --replace-fail ':ui/radix-color                        (storage/get :ui/radix-color)' ':ui/radix-color                        (or (storage/get :ui/radix-color) :pink)'
      '';
    });

  # ponytail: secretui is not in nixpkgs; bump this pinned release when updating.
  secretui = pkgs.rustPlatform.buildRustPackage rec {
    pname = "secretui";
    version = "0.1.4";
    src = pkgs.fetchFromGitHub {
      owner = "edwordout";
      repo = "secretui";
      rev = "v${version}";
      hash = "sha256-xqgNT0SYZlFYcU8JAq3d8TpYSVjIK6LftBSC8vwSLyU=";
    };
    cargoHash = "sha256-NX02kZA++qzSnYHLmZnKZePOfBPLKeRYd2yu1fR9ZyM=";
  };

  # ponytail: k0s is not in nixpkgs; bump this pinned release when updating.
  k0s = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "k0s";
    version = "1.36.4+k0s.0";
    src = pkgs.fetchurl {
      url = "https://github.com/k0sproject/k0s/releases/download/v${version}/k0s-v${version}-amd64";
      hash = "sha256-yh6eaBBzNYRugpZ3f84szWVChOYmW0tdMsNOrYcq+Y8=";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/k0s"
    '';
  };

  kindPodman = pkgs.writeShellApplication {
    name = "kind";
    text = ''
      export KIND_EXPERIMENTAL_PROVIDER=podman
      exec ${pkgs.kind}/bin/kind "$@"
    '';
  };

  oxkerPodman = pkgs.writeShellApplication {
    name = "oxker";
    text = ''
      export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
      exec ${pkgs.oxker}/bin/oxker "$@"
    '';
  };

  scaledVlc =
    let
      vlc = pkgs.vlc.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace modules/gui/qt/styles/seekstyle.cpp \
            --replace-fail 'QColor foregroundBase( 50, 156, 255 );' \
              'QColor foregroundBase = slideroptions->palette.color(QPalette::Highlight);'
        '';
      });
    in
    pkgs.symlinkJoin {
      name = "vlc-scaled";
      paths = [ vlc ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm "$out/bin/vlc"
        makeWrapper ${vlc}/bin/vlc "$out/bin/vlc" \
          --set QT_SCALE_FACTOR 1.6

        desktop="$out/share/applications/vlc.desktop"
        rm "$desktop"
        cp ${vlc}/share/applications/vlc.desktop "$desktop"
        substituteInPlace "$desktop" \
          --replace-fail "Exec=${vlc}/bin/vlc" "Exec=$out/bin/vlc"
      '';
      meta = vlc.meta // {
        outputsToInstall = [ "out" ];
      };
    };

  dmsVivaldi =
    (pkgs.vivaldi.override {
      proprietaryCodecs = true;
      enableWidevine = true;
      commandLineArgs = "--force-device-scale-factor=${toString browserScale.vivaldi}";
    }).overrideAttrs
      (old: {
        postFixup = (old.postFixup or "") + ''
          prefs="$out/opt/vivaldi/resources/vivaldi/prefs_definitions.json"
          bundle="$out/opt/vivaldi/resources/vivaldi/bundle.js"
          css="$out/opt/vivaldi/resources/vivaldi/style/common.css"
          for bookmarks in "$out/opt/vivaldi/resources/vivaldi/default-bookmarks/"*.json; do
            ${pkgs.jq}/bin/jq '
              if has("version") and has("children") then
                .version = "1000" | .children = []
              else
                .
              end
            ' "$bookmarks" > "$bookmarks.tmp"
            mv "$bookmarks.tmp" "$bookmarks"
          done
          ${pkgs.jq}/bin/jq '
            .vivaldi.bookmarks.bar.visible.default = true
            | .vivaldi.homepage.default = "about:blank"
            | .vivaldi.startup.check_is_default.default = false
            | .vivaldi.tabs.new_page.link.default = "blankpage"
            | .vivaldi.theme.schedule.enabled.default = "off"
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
          substituteInPlace "$bundle" \
            --replace-fail \
              'const o=e[0],a=o.children.find((e=>e.id===t.bookmarks));if(!a)return void console.error("Root bookmark id missing");' \
              'const o=e[0],a=o.children.find((e=>e.id===t.bookmarks)),r=o.children.find((e=>"managed"===e.folderType)),m=r?.children?.[0];if(!a)return void console.error("Root bookmark id missing");m&&(m.parentId=a.id,m.index=a.children.length,a.children.push(m));'
          chmod u+w "$css"
          printf '%s\n' \
            '#browser .menu, #browser .menubar { font-size: 11px; }' \
            '#browser .tab .title { font-size: 13.5px; }' \
            '#browser .UrlBar-UrlField { font-size: 14px; }' \
            '#browser .bookmark-bar { font-size: 15px; }' \
            >> "$css"
        '';
      });

  compactDms = pkgs.dms-shell.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      qml="$out/share/quickshell/dms/Modals/Clipboard/ClipboardConstants.qml"
      gtk="$out/share/quickshell/dms/matugen/templates/gtk-colors.css"
      qt="$out/share/quickshell/dms/scripts/qt.sh"
      shell="$out/share/quickshell/dms/DMSShell.qml"
      tray="$out/share/quickshell/dms/Modules/DankBar/Widgets/SystemTrayBar.qml"
      chmod u+w "$qml" "$gtk" "$qt" "$shell" "$tray"
      substituteInPlace "$qml" \
        --replace-fail 'readonly property int modalWidth: 650' 'readonly property int modalWidth: 520' \
        --replace-fail 'readonly property int modalHeight: 550' 'readonly property int modalHeight: 440' \
        --replace-fail 'readonly property int popoutWidth: 550' 'readonly property int popoutWidth: 440' \
        --replace-fail 'readonly property int popoutHeight: 500' 'readonly property int popoutHeight: 400' \
        --replace-fail 'readonly property int itemHeight: 72' 'readonly property int itemHeight: 64' \
        --replace-fail 'readonly property int thumbnailSize: 100' 'readonly property int thumbnailSize: 88' \
        --replace-fail 'readonly property int keyboardHintsHeight: 80' 'readonly property int keyboardHintsHeight: 64'
      # Use DMS's native qtct palette. The KDE palette requires qt5ct-kde, which nixpkgs no longer ships.
      substituteInPlace "$qt" \
        --replace-fail 'color_scheme_path="$(dirname "$config_dir")/.local/share/color-schemes/DankMatugen.colors"' 'color_scheme_path="$config_dir/qt5ct/colors/matugen.conf"'
      substituteInPlace "$shell" \
        --replace-fail $'id: polkitAuthModalLoader\n        active: false' $'id: polkitAuthModalLoader\n        active: true'
      substituteInPlace "$tray" \
        --replace-fail 'font.pixelSize: Theme.fontSizeSmall' 'font.pixelSize: Theme.fontSizeMedium'
      cat >> "$gtk" <<'EOF'

      popover.background modelbutton.flat:hover,
      popover.background .menuitem.button.flat:hover,
      menu menuitem:hover,
      .menu menuitem:hover,
      .context-menu menuitem:hover {
        color: @accent_fg_color;
        background-color: @accent_bg_color;
      }
      EOF
    '';
  });

  dmsSystemAppTheming = pkgs.writeShellApplication {
    name = "dms-system-app-theming";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      libsForQt5.qt5ct
      qt6Packages.qt6ct
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
      | .fontScale = ${toString desktopScale}
      | .controlCenterShowBluetoothIcon = true
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
          | .fontScale = ${toString desktopScale}
          | .iconScale = 1.1
          | .rightWidgets |= map(select((if type == "string" then . else .id end) != "exampleEmojiPlugin"))
        ))
    ' "$settings" > "$tmp"
    ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$settings"
  '';

  # ponytail: Helium rewrites Web Store URLs. Bump these local CRXs manually.
  authenticatorCrx = pkgs.fetchurl {
    url = "https://clients2.googleusercontent.com/crx/blobs/Abe5cL458nEmTqOKNQyZ01AEqeK2rOU0Y4XGFmFDAUYexkMFVImzGXDOTGILdb_yUxaSdMsxbq2r0SFYicdcQD-98DAKcpS7uFYOyxsmDbW754CsTbuMNyOVPGfQ00RIAKB3AMZSmuWq5oi9v3bUiQySLMFoNrwVCDJHTg/BHGHOAMAPCDPBOHPHIGOOOADDINPKBAI_8_0_1_0.crx";
    hash = "sha256-zyHVeLo7swr2xMostJXomhMpasoKPhRn2Vc1HXlAu7I=";
  };

  autoScrollCrx = pkgs.fetchurl {
    url = "https://clients2.googleusercontent.com/crx/blobs/Abe5cL6HYia7ln_elS710xpcr7o2VN-rKhkRUQXDtKLXZkT0PKYmI7K0Vf85MmsM2TSyxSJyTjcpclYalN0K5kGfBqk-MeSCSgqzQKulge3hpWeeSubCAMZSmuVvDe8OSn6A2VDEb4YRzxjhKPf-Aw/OCCJJKGIFPMDGODLPLNACMKEJPDIONAN_4_10_0_0.crx";
    hash = "sha256-JVJHIv+IZmimuvMbDwWHJ4DnHp+kOvFzo1IbAuhzldU=";
  };

  heliumExtensionUpdates = pkgs.writeText "helium-extension-updates.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0">
      <app appid="bhghoamapcdpbohphigoooaddinpkbai">
        <updatecheck codebase="file://${authenticatorCrx}" version="8.0.1" />
      </app>
      <app appid="occjjkgifpmdgodlplnacmkejpdionan">
        <updatecheck codebase="file://${autoScrollCrx}" version="4.10" />
      </app>
    </gupdate>
  '';

  heliumPolicies = builtins.toJSON (
    (builtins.removeAttrs browserPolicies [ "ExtensionInstallForcelist" ])
    // {
      ExtensionSettings."bhghoamapcdpbohphigoooaddinpkbai" = {
        installation_mode = "force_installed";
        toolbar_pin = "force_pinned";
        update_url = "file://${heliumExtensionUpdates}";
      };
      ExtensionSettings."occjjkgifpmdgodlplnacmkejpdionan" = {
        installation_mode = "force_installed";
        update_url = "file://${heliumExtensionUpdates}";
      };
      ManagedBookmarks = managedBookmarks;
    }
  );

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
          --add-flags "--force-device-scale-factor=${toString browserScale.helium} --top-chrome-touch-ui=disabled --gtk-version=3"
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
    fira-code
    gh
    gimp
    go
    cheese
    helium
    inter
    jetbrains-toolbox
    k0s
    k3s
    karere
    kindPodman
    logseq
    lsd
    opentofu
    oxkerPodman
    papirusPink
    pear-desktop
    pdfarranger
    podman-compose
    python3
    qbittorrent
    ristretto
    rustc
    rustfmt
    secretui
    signal-desktop
    spotify
    swappy
    telegram-desktop
    terraform
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
    platformTheme.name = "qtct";
    qt5ctSettings = {
      Appearance = qtAppearance;
      Fonts = qtFonts;
      Interface.stylesheets = "${qt5MenuStyle}";
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

  programs.bash.enable = true;
  programs.nushell = {
    enable = true;
    settings.show_banner = false;
  };

  programs.carapace = {
    enable = true;
    enableBashIntegration = false;
    enableNushellIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableNushellIntegration = true;
    settings = {
      add_newline = false;
      command_timeout = 200;
      scan_timeout = 10;
      format = "[╭─](bold #e91e63) $username$hostname$directory$git_branch$git_status$nix_shell$golang$rust$zig$cmd_duration$status$jobs$fill$time$line_break[╰─](bold #e91e63) $shell$character";
      username = {
        format = "[$user]($style)";
        show_always = false;
        style_root = "bold red";
        style_user = "bold #f0dee0";
      };
      hostname = {
        format = "[@$hostname]($style) ";
        ssh_only = true;
        style = "bold #e91e63";
      };
      directory = {
        format = "[$path]($style)";
        read_only = " ro";
        style = "bold #e91e63";
        truncate_to_repo = true;
        truncation_length = 2;
      };
      git_branch = {
        format = " [git:$branch]($style)";
        style = "bold #f0dee0";
      };
      git_status = {
        ahead = " ^";
        behind = " v";
        conflicted = " =";
        deleted = " x";
        diverged = " <>";
        format = "([$all_status$ahead_behind]($style))";
        modified = " !";
        renamed = " r";
        staged = " +";
        stashed = " *";
        style = "bold #e91e63";
        untracked = " ?";
      };
      nix_shell = {
        format = " [nix:$state( $name)]($style)";
        style = "bold blue";
      };
      golang = {
        format = " [go $version]($style)";
        style = "bold cyan";
      };
      rust = {
        format = " [rust $version]($style)";
        style = "bold red";
      };
      zig = {
        format = " [zig $version]($style)";
        style = "bold yellow";
      };
      cmd_duration = {
        format = " [took $duration]($style)";
        min_time = 1000;
        style = "dimmed #f0dee0";
      };
      status = {
        disabled = false;
        format = " [exit $status]($style)";
        style = "bold red";
      };
      jobs = {
        format = " [$symbol$number]($style)";
        style = "bold blue";
        symbol = "jobs:";
      };
      fill.symbol = " ";
      shell = {
        bash_indicator = "bash";
        disabled = false;
        format = "[$indicator]($style) ";
        nu_indicator = "nu";
        style = "bold blue";
      };
      time = {
        disabled = false;
        format = " [$time]($style)";
        style = "dimmed #f0dee0";
        time_format = "%H:%M";
      };
      character = {
        error_symbol = "[>](bold red)";
        success_symbol = "[>](bold #e91e63)";
      };
    };
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
      DisplayBookmarksToolbar = "always";
      DontCheckDefaultBrowser = true;
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
      NoDefaultBookmarks = true;
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
      "image/bmp" = [ "org.xfce.ristretto.desktop" ];
      "image/gif" = [ "org.xfce.ristretto.desktop" ];
      "image/jpeg" = [ "org.xfce.ristretto.desktop" ];
      "image/png" = [ "org.xfce.ristretto.desktop" ];
      "image/svg+xml" = [ "org.xfce.ristretto.desktop" ];
      "image/tiff" = [ "org.xfce.ristretto.desktop" ];
      "image/webp" = [ "org.xfce.ristretto.desktop" ];
      "image/x-pixmap" = [ "org.xfce.ristretto.desktop" ];
      "image/x-xpixmap" = [ "org.xfce.ristretto.desktop" ];
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

  services.kanshi = {
    enable = true;
    systemdTarget = "niri.service";
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

  # Audacity themes its editor separately from GTK.
  home.activation.audacityDarkTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.config/audacity/audacity.cfg"
    run ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$settings")"
    run ${pkgs.crudini}/bin/crudini --set "$settings" GUI Theme dark
  '';

  home.activation.dmsSystemAppTheming = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    run ${dmsSystemAppTheming}/bin/dms-system-app-theming
  '';

  home.activation.signalSystemTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.config/Signal/ephemeral.json"
    [[ -f "$settings" ]] || exit 0
    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    ${pkgs.jq}/bin/jq '."theme-setting" = "system"' "$settings" > "$tmp"
    ${pkgs.coreutils}/bin/install -m 600 "$tmp" "$settings"
  '';

  xdg.configFile = {
    "carapace/specs/lsd.yaml".source = ./carapace-lsd.yaml;
    "gtk-3.0/settings.ini".force = true;
    "gtk-4.0/settings.ini".force = true;
    "kanshi/config".text = ''
      profile {
        ...output "*" scale ${toString desktopScale}
      }
    '';
    "niri/config.kdl".source = niriConfig;
    "qt5ct/qt5ct.conf".force = true;
    "qt6ct/qt6ct.conf".force = true;
    "zen/smo9aotg.Default Profile/chrome/userChrome.css" = {
      force = true;
      text = ''@import url("file://${config.xdg.configHome}/DankMaterialShell/zen.css");'';
    };
    "zen/smo9aotg.Default Profile/user.js" = {
      force = true;
      text = ''user_pref("zen.view.use-single-toolbar", false);'';
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
