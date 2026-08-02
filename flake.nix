{
  description = "Anthropic's official Claude Desktop app, packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Claude Desktop ships an x86_64 Linux build only.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          # Claude Desktop is proprietary (unfree); allow it so the package
          # output builds directly (`nix run`/`nix build`) without --impure.
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        rec {
          claude-desktop = pkgs.callPackage ./package.nix { };
          default = claude-desktop;
        }
      );

      # Apply with `nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];`
      # then refer to `pkgs.claude-desktop` anywhere as a native package.
      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
