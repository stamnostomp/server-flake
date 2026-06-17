{ config, pkgs, ... }:

{
  imports = [ ];

  nixpkgs.config.allowUnfree = true;

  # ── Boot ─────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VirtIO / Proxmox kernel modules
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "ahci"
    "xhci_pci"
    "usbhid"
  ];
  boot.kernelModules = [ "kvm-intel" ]; # swap for kvm-amd if Proxmox host is AMD

  # ── Networking ───────────────────────────────────────────────────────────
  networking.hostName = "server"; # change to taste
  networking.networkmanager.enable = true;

  # ── Locale / time ────────────────────────────────────────────────────────
  time.timeZone = "America/New_York"; # change to your timezone
  i18n.defaultLocale = "en_US.UTF-8";

  # ── NVIDIA (headless compute, GTX 1060 Pascal) ───────────────────────────
  # GTX 1060 does NOT support the open-source kernel module (requires Turing+)
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = false; # no GUI settings panel needed
    powerManagement.enable = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Loading the driver without an X display server
  services.xserver.videoDrivers = [ "nvidia" ];
  services.xserver.enable = false;

  # NVIDIA container toolkit — lets Docker containers access the GPU
  hardware.nvidia-container-toolkit.enable = true;

  # ── Docker ───────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    # Expose GPU to containers via CDI (populated by nvidia-container-toolkit)
    daemon.settings = {
      features.cdi = true;
    };
  };

  # ── QEMU guest agent (Proxmox integration) ────────────────────────────────
  services.qemuGuest.enable = true;

  # ── SSH ──────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ── Users ────────────────────────────────────────────────────────────────
  users.users.stamno = {
    # change username if needed
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      # Paste your public SSH key here, e.g.:
      # "ssh-ed25519 AAAA... user@host"
    ];
  };

  # Allow wheel group to sudo without password (remove if you prefer prompted)
  security.sudo.wheelNeedsPassword = false;

  # ── System packages ───────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    htop
    nvtopPackages.nvidia # GPU process monitor
    docker-compose
    pciutils # lspci — useful to verify GPU passthrough
    usbutils
  ];

  # ── Nix settings ─────────────────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
