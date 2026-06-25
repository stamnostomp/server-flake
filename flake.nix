{
  description = "NixOS server - Proxmox VM with GTX 1060 PCIe passthrough";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { hasGpu = true; };
      modules = [
        ./nixos/configuration.nix
        ./nixos/hardware-configuration.nix
      ];
    };

    # Same as `server` but without the NVIDIA/GPU bits — for a VM/host with no GPU passthrough.
    nixosConfigurations.server-nogpu = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { hasGpu = false; };
      modules = [
        ./nixos/configuration.nix
        ./nixos/hardware-configuration.nix
        { networking.hostName = "server-nogpu"; }
      ];
    };

    nixosConfigurations.game-servers = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos/game-servers/configuration.nix
        ./nixos/game-servers/hardware-configuration.nix
      ];
    };
  };
}
