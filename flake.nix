{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
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
      home-manager,
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
      };
    in
    {
      lib = {
        inherit browserPolicies personalBookmarks;
      };

      nixosModules.default = {
        imports = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          dank-greeter.nixosModules.default
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
