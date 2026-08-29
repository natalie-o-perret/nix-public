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
        { toplevel_name = "Starter links"; }
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
    in
    {
      lib.personalBookmarks = personalBookmarks;

      nixosModules.default = {
        imports = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          dank-greeter.nixosModules.default
        ];

        environment.etc."vivaldi/policies/managed/bookmarks.json".text =
          builtins.toJSON { ManagedBookmarks = personalBookmarks; };

        home-manager = {
          extraSpecialArgs.managedBookmarks = personalBookmarks;
          sharedModules = [
            dms.homeModules.dank-material-shell
            zen-browser.homeModules.beta
          ];
        };
      };
    };
}
