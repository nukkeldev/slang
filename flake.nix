{
  description = "Zig Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/0e6386787aaa25cf8d4ba104ba0621519bbec0f1";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        {
          formatter = pkgs.nixfmt-rfc-style;

          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              # zig
              zls
              zig_0_14
            ];
          };
        };
    };
}
