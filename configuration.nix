{ pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;

  time.timeZone = "Europe/Paris";

  i18n.defaultLocale = "en_US.UTF-8";
  environment.sessionVariables.TERMINAL = "ghostty";

  services.desktopManager.cosmic.enable = true;
  services.displayManager.defaultSession = "niri";

  programs = {
    dms-greeter = {
      enable = true;
      compositor.name = "niri";
      configHome = "/home/nperret";
    };
    niri = {
      enable = true;
      useNautilus = false;
    };
    thunar.enable = true;
  };

  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.udisks2.enable = true;
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # DMS uses these system services from the user session.
  services.accounts-daemon.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  virtualisation.podman.enable = true;

  users.users.nperret = {
    isNormalUser = true;
    description = "Natalie Perret";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.nperret = import ./home.nix;
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  system.stateVersion = "26.05";
}
