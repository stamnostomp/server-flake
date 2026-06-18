{ config, pkgs, lib, ... }:

{
  imports = [ ];

  nixpkgs.config.allowUnfree = true;

  # ── Boot ─────────────────────────────────────────────────────────────────
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
    "ahci"
    "xhci_pci"
    "usbhid"
  ];
  boot.kernelModules = [ "kvm-intel" ]; # swap for kvm-amd if host is AMD

  # ── Networking ───────────────────────────────────────────────────────────
  networking.hostName = "game-servers";
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (Pterodactyl Panel)
      443   # HTTPS (Pterodactyl Panel)
      2022  # Pterodactyl Wings SFTP
      8080  # Pterodactyl Wings API
      8081  # MinePanel (update if different)
    ];
    # Game server port range — widen or narrow to match your allocations
    allowedTCPPortRanges = [
      { from = 25565; to = 25600; }
    ];
    allowedUDPPortRanges = [
      { from = 25565; to = 25600; }
    ];
  };

  # ── Locale / time ────────────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Docker ───────────────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # Create a dedicated Docker network for Pterodactyl containers so they can
  # reach each other by name (database, cache, panel).  Wings uses host
  # networking so it can bind directly to game-server ports.
  systemd.services.pterodactyl-network-setup = {
    description = "Ensure pterodactyl Docker network exists";
    wantedBy = [ "multi-user.target" ];
    before = [
      "docker-pterodactyl-database.service"
      "docker-pterodactyl-cache.service"
      "docker-pterodactyl-panel.service"
      "docker-minepanel.service"
    ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # "|| true" is intentional: the command errors if the network already exists
      ExecStart = "${pkgs.docker}/bin/docker network create pterodactyl --subnet=172.20.0.0/16 || true";
    };
  };

  # ── Pterodactyl + MinePanel containers ───────────────────────────────────
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {

      # MariaDB — Pterodactyl Panel database
      pterodactyl-database = {
        image = "mariadb:10.5";
        extraOptions = [ "--network=pterodactyl" ];
        environment = {
          MYSQL_ROOT_PASSWORD = "CHANGE_ROOT_PASSWORD";
          MYSQL_DATABASE      = "panel";
          MYSQL_USER          = "pterodactyl";
          MYSQL_PASSWORD      = "CHANGE_DB_PASSWORD";
        };
        volumes = [ "/srv/pterodactyl/database:/var/lib/mysql" ];
      };

      # Redis — session / queue / cache store for the Panel
      pterodactyl-cache = {
        image = "redis:alpine";
        extraOptions = [ "--network=pterodactyl" ];
        volumes = [ "/srv/pterodactyl/cache:/data" ];
      };

      # Pterodactyl Panel — web UI
      # After deploy: create the first admin user with
      #   docker exec -it pterodactyl-panel php artisan p:user:make
      pterodactyl-panel = {
        image = "ghcr.io/pterodactyl/panel:latest";
        extraOptions = [ "--network=pterodactyl" ];
        ports = [
          "80:80"
          "443:443"
        ];
        environment = {
          APP_URL             = "https://CHANGE_TO_YOUR_DOMAIN";
          APP_TIMEZONE        = "America/New_York";
          APP_SERVICE_AUTHOR  = "admin@CHANGE_TO_YOUR_DOMAIN";
          DB_HOST             = "pterodactyl-database";
          DB_PORT             = "3306";
          DB_DATABASE         = "panel";
          DB_USERNAME         = "pterodactyl";
          DB_PASSWORD         = "CHANGE_DB_PASSWORD";
          CACHE_DRIVER        = "redis";
          SESSION_DRIVER      = "redis";
          QUEUE_DRIVER        = "redis";
          REDIS_HOST          = "pterodactyl-cache";
          REDIS_PORT          = "6379";
        };
        volumes = [
          "/srv/pterodactyl/var:/app/var"
          "/srv/pterodactyl/nginx:/etc/nginx/http.d"
          "/srv/pterodactyl/certs:/etc/letsencrypt"
          "/srv/pterodactyl/logs:/app/storage/logs"
        ];
        dependsOn = [ "pterodactyl-database" "pterodactyl-cache" ];
      };

      # Pterodactyl Wings — game server daemon
      # Before first start, generate a config from the Panel:
      #   Admin → Nodes → <this node> → Configuration tab → copy YAML
      #   Save it to /etc/pterodactyl/config.yml on this host.
      pterodactyl-wings = {
        image = "ghcr.io/pterodactyl/wings:latest";
        # Wings must use host networking so it can bind to game-server ports
        # directly and communicate with game containers.
        extraOptions = [ "--network=host" "--pid=host" ];
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
          "/var/lib/pterodactyl:/var/lib/pterodactyl"
          "/etc/pterodactyl:/etc/pterodactyl"
          "/var/log/pterodactyl:/var/log/pterodactyl"
          "/tmp/pterodactyl:/tmp/pterodactyl"
          "/etc/ssl/certs:/etc/ssl/certs:ro"
        ];
        dependsOn = [ "pterodactyl-panel" ];
      };

      # MinePanel — replace image with the correct one when known
      minepanel = {
        image = "REPLACE_WITH_MINEPANEL_IMAGE";
        extraOptions = [ "--network=pterodactyl" ];
        ports = [ "8081:8081" ];
        volumes = [ "/srv/minepanel/data:/data" ];
      };

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

  security.sudo.wheelNeedsPassword = false;

  # ── System packages ───────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    htop
    docker-compose
    pciutils
    usbutils
  ];

  # ── Nix settings ─────────────────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
