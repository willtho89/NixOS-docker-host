{
  description = "Single-server NixOS VPS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, ... }:
    let
      repoHostConfigPath = ./host-config.nix;
      envHostConfigPath = builtins.getEnv "HOST_CONFIG_PATH";
      hostConfigPath =
        if builtins.pathExists repoHostConfigPath then
          repoHostConfigPath
        else if envHostConfigPath == "" then
          ./host-config.example.nix
        else if builtins.substring 0 1 envHostConfigPath != "/" then
          throw "HOST_CONFIG_PATH must be an absolute path"
        else
          /. + envHostConfigPath;
      hostConfig = import hostConfigPath;

      systemConfig = nixpkgs.lib.nixosSystem {
        system = hostConfig.system;
        specialArgs = {
          inherit hostConfig;
        };
        modules = [
          disko.nixosModules.disko
          ./disko-config.nix
          ./configuration.nix
        ];
      };
    in
    {
      nixosConfigurations.server = systemConfig;
      nixosConfigurations.${hostConfig.hostName} = systemConfig;
    };
}
