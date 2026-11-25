{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    opencode-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    signal-nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:duxlabs-dev/dux-shell/v2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-calendar = {
      url = "github:duxlabs-dev/dux-calendar/v2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-files = {
      url = "github:duxlabs-dev/dux-files/v2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-gop = {
      url = "github:duxlabs-dev/dux-gop/v2.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-greeter = {
      url = "github:duxlabs-dev/dux-greeter/v2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-search = {
      url = "github:duxlabs-dev/dux-search/v2.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      dms,
      dux-calendar,
      dux-files,
      dux-gop,
      dux-greeter,
      dux-search,
      home-manager,
      nixpkgs,
      opencode-nixpkgs,
      self,
      signal-nixpkgs,
      zen-browser,
      ...
    }:
    let
      personalBookmarks = [
        {
          name = "Personal";
          children = [
            {
              name = "MDN Web Docs";
              url = "https://developer.mozilla.org/";
            }
          ];
        }
      ];
      browserPolicies = {
        BookmarkBarEnabled = true;
        DefaultBrowserSettingEnabled = false;
        DefaultSearchProviderContextMenuAccessAllowed = true;
        DefaultSearchProviderEnabled = true;
        DefaultSearchProviderImageURL = "https://lens.google.com/upload";
        DefaultSearchProviderImageURLPostParams = "encoded_image={google:imageThumbnail}";
        DefaultSearchProviderKeyword = "google.com";
        DefaultSearchProviderName = "Google";
        DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
        DefaultSearchProviderSuggestURL = "https://www.google.com/complete/search?client=chrome&q={searchTerms}";
        ExtensionInstallForcelist = [
          "bhghoamapcdpbohphigoooaddinpkbai;https://clients2.google.com/service/update2/crx"
          "occjjkgifpmdgodlplnacmkejpdionan;https://clients2.google.com/service/update2/crx"
        ];
        HomepageIsNewTabPage = false;
        HomepageLocation = "about:blank";
        NewTabPageLocation = "about:blank";
        RestoreOnStartup = 4;
        RestoreOnStartupURLs = [ "about:blank" ];
        SpellcheckLanguage = [
          "en-US"
          "fr"
        ];
      };
    in
    {
      lib = {
        inherit browserPolicies personalBookmarks;
      };

      checks.x86_64-linux.signal-theme =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          host = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ self.nixosModules.default ];
          };
          activation = pkgs.writeShellScript "signal-theme-test" ''
            ${host.config.home-manager.users.nperret.home.activation.signalSystemTheme.data}
            touch "$HOME/continued"
          '';
        in
        pkgs.runCommand "signal-theme-test" { nativeBuildInputs = [ pkgs.jq ]; } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          ${activation}
          test -e "$HOME/continued"
          test ! -e "$HOME/.config/Signal"
          rm "$HOME/continued"
          mkdir -p "$HOME/.config/Signal"
          echo '{"theme-setting":"dark","keep":true}' > "$HOME/.config/Signal/ephemeral.json"
          ${activation}
          test -e "$HOME/continued"
          jq -e '."theme-setting" == "system" and .keep == true' "$HOME/.config/Signal/ephemeral.json"
          test "$(stat -c %a "$HOME/.config/Signal/ephemeral.json")" = 600
          touch "$out"
        '';

      nixosModules.default = {
        imports = [
          ./configuration.nix
          dux-files.nixosModules.default
          dux-greeter.nixosModules.default
          home-manager.nixosModules.home-manager
        ];

        nixpkgs.overlays = [
          (
            final: _:
            let
              aiPackages = import opencode-nixpkgs {
                system = final.stdenv.hostPlatform.system;
                config.allowUnfree = true;
              };
            in
            {
              claude-code = aiPackages.claude-code;
              dgop = dux-gop.packages.${final.stdenv.hostPlatform.system}.dgop;
              # Keep the desktop's Qt stack while supplying DMS's required Go patch version.
              dms-shell = dms.lib.mkDmsShell (final // { go_1_27 = aiPackages.go_1_27; });
              dux-files = dux-files.lib.mkDfiles (final // { go_1_27 = aiPackages.go_1_27; });
              dux-images = final.callPackage ./image-viewer {
                dcommon = dux-files.inputs.dank-qml-common;
              };
              opencode = aiPackages.opencode;
              # Update Signal without moving the desktop package set.
              signal-desktop = signal-nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system}.signal-desktop;
            }
          )
        ];

        environment.etc."vivaldi/policies/managed/bookmarks.json".text = builtins.toJSON {
          ManagedBookmarks = [
            {
              name = "Managed bookmarks";
              children = personalBookmarks;
            }
          ];
        };
        environment.etc."vivaldi/policies/managed/browser.json".text = builtins.toJSON browserPolicies;

        home-manager = {
          extraSpecialArgs = {
            inherit browserPolicies;
            managedBookmarks = personalBookmarks;
          };
          sharedModules = [
            dms.homeModules.dank-material-shell
            dux-calendar.homeModules.default
            dux-search.homeModules.default
            zen-browser.homeModules.beta
          ];
        };
      };
    };
}
