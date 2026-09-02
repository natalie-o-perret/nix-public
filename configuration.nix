{ pkgs, ... }:

let
  grubTheme = pkgs.runCommand "nixos-grub-theme" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    cp -r ${pkgs.kdePackages.breeze-grub}/grub/themes/breeze "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/theme.txt" \
      --replace-fail 'Unifont Regular 14' 'DejaVu Sans Mono Regular 32' \
      --replace-fail 'Unifont Regular 16' 'DejaVu Sans Mono Regular 32' \
      --replace-fail 'Unifont Bold 16' 'DejaVu Sans Mono Regular 32' \
      --replace-fail 'top = 50%-225' 'top = 50%-325' \
      --replace-fail 'left = 50%-400' 'left = 50%-600' \
      --replace-fail 'width = 800' 'width = 1200' \
      --replace-fail 'top = 50%-150' 'top = 50%-250' \
      --replace-fail 'height = 200' 'height = 400' \
      --replace-fail 'item_height = 33' 'item_height = 48' \
      --replace-fail 'left = 50%-200' 'left = 50%-600' \
      --replace-fail 'top = 50%+113' 'top = 50%+240' \
      --replace-fail 'top = 50%+66' 'top = 50%+195' \
      --replace-fail 'width = 400' 'width = 1200' \
      --replace-fail 'height = 19' 'height = 44' \
      --replace-fail '#7f8c8d' '#b7b7c2' \
      --replace-fail 'color = "#ffffff"' 'color = "#e91e63"' \
      --replace-fail 'text_color = "#b7b7c2"' 'text_color = "#e91e63"' \
      --replace-fail 'desktop-color: "#000000"' 'desktop-color: "#0b0b0f"'
    magick -size 1x32 'xc:#e91e63' "$out/progress_bar_hl_c.png"
  '';
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  boot.loader = {
    timeout = 5;
    efi.canTouchEfiVariables = true;
    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      efiInstallAsRemovable = false;
      configurationLimit = 50;
      splashImage = null;
      theme = grubTheme;
      font = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
      fontSize = 32;
    };
  };

  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v32n.psf.gz";
  };

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;

  time.timeZone = "Europe/Paris";

  i18n.defaultLocale = "en_US.UTF-8";
  environment.sessionVariables.TERMINAL = "ghostty";

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
  security.polkit.enablePkexecWrapper = true;
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
