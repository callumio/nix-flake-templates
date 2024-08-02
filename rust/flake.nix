{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    crane,
  }:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        binary-name = "BINARY";
        image-name = "IMAGE";
        image-tag = "latest";

        rustToolchain = pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
        src = craneLib.cleanCargoSource ./.;

        nativeBuildInputs = with pkgs; [rustToolchain pkg-config];
        buildInputs = with pkgs; [udev];

        commonArgs = {
          inherit src buildInputs nativeBuildInputs;
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        bin = craneLib.buildPackage (commonArgs // {inherit cargoArtifacts;});

        rust-distroless = pkgs.dockerTools.pullImage {
          imageName = "gcr.io/distroless/cc-debian12";
          imageDigest = "sha256:3b75fdd33932d16e53a461277becf57c4f815c6cee5f6bc8f52457c095e004c8";
          sha256 = "0mkcbd4y3pm8nhqa3wxlswwyf9072q090wa4jabfp0f2r426645p";
          finalImageName = "gcr.io/distroless/cc-debian12";
          finalImageTag = "latest";
        };

        dockerImage = pkgs.dockerTools.streamLayeredImage {
          name = image-name;
          tag = image-tag;
          contents = [bin];
          fromImage = rust-distroless;
          config = {
            Cmd = ["${bin}/bin/${binary-name}"];
            Env = [];
          };
        };
      in
        with pkgs; {
          packages = {
            inherit bin dockerImage;
            default = bin;
          };
          devShells.default = mkShell {
            inputsFrom = [bin];
          };
        }
    );
}
