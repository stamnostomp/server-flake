{ config, pkgs, lib, hasGpu ? true, ... }:

{
  imports = [ ];

  nixpkgs.config.allowUnfree = true;

  # ── Boot ─────────────────────────────────────────────────────────────────
  # Legacy BIOS boot (SeaBIOS in Proxmox) — change /dev/vda to match your disk
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

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
  # 580.x is the last branch with full Pascal support (590 drops it); legacy_580
  # is nixpkgs' LTSB pin for that branch, supported through Aug 2028.
  # Set via specialArgs (see flake.nix `server-nogpu` output) to skip all of this.
  hardware.nvidia = lib.mkIf hasGpu {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = false; # no GUI settings panel needed
    powerManagement.enable = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  # Loading the driver without an X display server
  services.xserver.videoDrivers = lib.mkIf hasGpu [ "nvidia" ];
  services.xserver.enable = false;

  # NVIDIA container toolkit — lets Docker containers access the GPU
  hardware.nvidia-container-toolkit.enable = hasGpu;

  # ── Docker ───────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    # Expose GPU to containers via CDI (populated by nvidia-container-toolkit)
    daemon.settings = lib.mkIf hasGpu {
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHTApvf6GJQ9Jbym/qSTdICNOzLoGwzh9DYQwIE1aHuO stamno@stamno.com"
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
    docker-compose
    pciutils # lspci — useful to verify GPU passthrough
    usbutils
  ] ++ lib.optionals hasGpu [ pkgs.nvtopPackages.nvidia ]; # GPU process monitor

  # ── Nix settings ─────────────────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
