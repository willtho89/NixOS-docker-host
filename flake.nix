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
      hostConfigPath =
        let
          configuredPath = builtins.getEnv "HOST_CONFIG_PATH";
          pwd = builtins.getEnv "PWD";
        in
          if configuredPath != "" then
            configuredPath
          else if pwd != "" then
            "${pwd}/host-config.nix"
          else
            throw ''
              Missing host configuration path.
              Run Nix commands with --impure from the repository root, or set HOST_CONFIG_PATH to an absolute host-config.nix path.
            '';

      hostConfig =
        if builtins.pathExists hostConfigPath then
          import hostConfigPath
        else
          throw ''
            Missing host configuration: ${hostConfigPath}
            Copy ./host-config.example.nix to ./host-config.nix and fill in your machine-specific values.
          '';

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
