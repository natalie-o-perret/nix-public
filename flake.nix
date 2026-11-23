{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    opencode-nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:duxlabs-dev/dux-shell/v2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dux-files = {
      url = "github:duxlabs-dev/dux-files/v2.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      dank-greeter,
      dms,
      dux-files,
      home-manager,
      opencode-nixpkgs,
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

      nixosModules.default = {
        imports = [
          ./configuration.nix
          dux-files.nixosModules.default
          home-manager.nixosModules.home-manager
          dank-greeter.nixosModules.default
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
              # Keep the desktop's Qt stack while supplying DMS's required Go patch version.
              dms-shell = dms.lib.mkDmsShell (final // { go_1_27 = aiPackages.go_1_27; });
              dux-files = dux-files.lib.mkDfiles (final // { go_1_27 = aiPackages.go_1_27; });
              dux-images = final.callPackage ./image-viewer {
                dcommon = dux-files.inputs.dank-qml-common;
              };
              opencode = aiPackages.opencode;
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
            zen-browser.homeModules.beta
          ];
        };
      };
    };
}
