# nix-public

Reusable NixOS configuration for a Niri desktop powered by DankMaterialShell.

## Architecture

- `flake.nix` pins Nixpkgs, Home Manager, DMS, Zen Browser and the DMS greeter. It exports `nixosModules.default` and reusable browser/bookmark values under `lib`.
- `configuration.nix` defines the portable NixOS base: user, boot, networking, audio, printing, Podman, Niri and system services used by DMS.
- `home.nix` defines the user environment: applications, fonts, themes, browser policies, DMS integration and Home Manager settings.
- `niri.kdl` contains the compositor layout, bindings and environment.

Hardware-specific files are intentionally not included. Import `nixosModules.default` from a host flake alongside that host's generated `hardware-configuration.nix`.

## Use

```nix
{
  inputs.nix-public.url = "github:natalie-o-perret/nix-public";
  inputs.nixpkgs.follows = "nix-public/nixpkgs";

  outputs = { nix-public, nixpkgs, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-public.nixosModules.default
        ./hardware-configuration.nix
      ];
    };
  };
}
```

Then validate and switch:

```sh
nix flake check
sudo nixos-rebuild switch --flake .#nixos
```

The DMS theme is generated dynamically. GTK, Qt, Zen and Zed consume its generated color files; `Mod+Space`, then `:e`, opens the declarative emoji search.
