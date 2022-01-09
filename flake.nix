{
  description = "memflow physical memory introspection framework";

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    rust-overlay.url = github:oxalica/rust-overlay;
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        lib = pkgs.lib;

        # Function that creates the package derivation version string from the Cargo TOML version & git rev hash.
        # I'm including both the Cargo TOML version number and short VCS hash for disambiguation.
        projectVersion = cargoTOML: src: "${cargoTOML.package.version}+${builtins.substring 0 7 src.rev}";
      in
      {

        packages = {

          cglue-bindgen =
            let
              src = pkgs.fetchFromGitHub {
                owner = "h33p";
                repo = "cglue";
                # See: https://github.com/h33p/cglue/commits/main
                rev = "02e0f1089fe942edcda0391d12a008b6459bcc99";
                sha256 = "sha256-6+4ocKG9sAuZkT6AoOTBix3Sl6tifEXXexgo3w+YTC4=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/cglue-bindgen/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              cargoHash = "sha256-u/bsAY25HrGQNUeJaqZtFcwUHmi4Xw/ePIDAh9WJ7Zg=";
              cargoPatches = [ ./patches/0001-add_cglue_bindgen_Cargo.lock.patch ];

              nativeBuildInputs = with pkgs; [ makeWrapper ];

              # cbindgen 0.20 (see: https://git.io/J9Gk2) & Rust nightly are needed for cglue-bindgen:
              #   "ERROR: Parsing crate `memflow-ffi`: couldn't run `cargo rustc -Zunpretty=expanded`"
              #   "error: the option `Z` is only accepted on the nightly compiler"
              postInstall = ''
                wrapProgram $out/bin/cglue-bindgen \
                  --prefix PATH : ${lib.makeBinPath (with pkgs; [rust-cbindgen rust-bin.nightly.latest.default ])}
              '';

              meta = with cargoTOML.package; {
                inherit description;
                homepage = repository;
                downloadPage = https://github.com/h33p/cglue/releases;
                license = lib.licenses.mit;
              };
            };

          memflow =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow";
                # See: https://github.com/memflow/memflow/commits/next
                rev = "9461991d83937859a76648339c0587735f6d64ee";
                sha256 = "sha256-nHNtWjswYWnzYOQ6v86ApvcvhY3XiAwAQJINax2nbzw=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              patches = [
                # The default bindgen wrapper script tries to use rustup to download Rust nightly. We can't download
                # stuff in the build sandbox and it isn't hermetic anyways, plus our cglue-bindgen derivation is already
                # wrapped with nightly.
                ./patches/0002-memflow_ffi_cglue_bindgen_script.patch
              ];

              # Test suites are often failing for next branch commits since it's bleeding edge. Sometimes non-passing
              # commits include important fixes so we'll pin each package derivation to use a known working commit.
              doCheck = false;
              # Since memflow is still pre-v1 include debugging symbols for easier troubleshooting of potential crashes
              # and issues. You can override this attribute if you want release builds with high performance.
              # See: https://nixos.org/manual/nixpkgs/stable/#building-a-package-in-debug-mode
              buildType = "debug";
              dontStrip = true; # See above

              nativeBuildInputs = with pkgs; [
                self.packages.${system}.cglue-bindgen
              ];

              cargoHash = "sha256-Mj23+M4ws+ZfaDop0QisTLCMjtTftgrQDr3cQNNSvXc=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              outputs = [ "dev" "out" ]; # Create outputs for the FFI shared library & development headers

              postBuild = ''
                # Delete any pregenerated FFI headers, we'll produce our own in this derivation
                rm -f ./memflow-ffi/*.h{,pp}
                # Create FFI development headers using the patched script
                cd ./memflow-ffi/
                bash ./bindgen.sh
                # Put header files into dev output folder
                mkdir -vp "$dev/include/memflow/"
                cp -v ./memflow.h{,pp} "$dev/include/memflow/"
                # Return to pwd otherwise builder will be upset
                cd ../.
              '';

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow/releases;
                license = licenses.mit;
              };
            };

          memflow-win32 =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-win32";
                rev = "e94c7120296b0fc0404fe79b41f87f646362c28e";
                # See: https://github.com/memflow/memflow-win32/commits/main
                sha256 = "sha256-RQwbw7k4DZfrcDP0RHCb8k/4v4HshcjSVlzq9PtOOis=";
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              pname = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              buildType = "debug";
              dontStrip = true;

              cargoHash = "sha256-nRFbisI2sNoORPewogZxK0p/Q0AUP662PYP9h/+Gj98=";
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-win32/releases;
                license = licenses.mit;
              };
            });

          memflow-kvm =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-kvm";
                # See: https://github.com/memflow/memflow-kvm/commits/next
                rev = "1c2875522fbe4d29df61d23e69233debabf8f198";
                sha256 = "sha256-Nashl1rt5iobmD5w+E4Ct1/FYzwGkSw2eYgSNbTRix0=";
                fetchSubmodules = true;
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/memflow-kvm/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              name = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              buildType = "debug";
              dontStrip = true;

              RUST_BACKTRACE = "full";
              LIBCLANG_PATH = "${pkgs.libclang.lib}/lib/"; # "thread 'main' panicked at 'Unable to find libclang"

              cargoHash = "sha256-QbdxPdLMBAmDho3j0M2dWFhJjYaa2TyREAY4Wec5nz4=";
              # Compile the KVM connector in the same way memflowup does to ensure it contains necessary exports
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              buildInputs = with pkgs; [
                llvmPackages.libclang
              ];
              nativeBuildInputs = with pkgs; [
                # FIXME: not sure what the correct package to use here is?
                rust-bindgen # "./mabi.h:14:10: fatal error: 'linux/types.h' file not found"
              ];

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-kvm/releases;
                license = licenses.mit;
              };
            });

          memflow-qemu =
            let
              src = pkgs.fetchFromGitHub {
                owner = "memflow";
                repo = "memflow-qemu";
                # See: https://github.com/memflow/memflow-qemu/tree/next
                rev = "1b6ab1ff69188b800f9c02c63cd2c0cd86796125";
                sha256 = "sha256-DpGdPTckq8wH/5R0kKOZbz+piRSX/5yzdFOchck1Xmw=";
                fetchSubmodules = true;
              };
              cargoTOML = (builtins.fromTOML (builtins.readFile (src + "/Cargo.toml")));
            in
            pkgs.rustPlatform.buildRustPackage (rec {
              name = cargoTOML.package.name;
              version = projectVersion cargoTOML src;

              inherit src;

              doCheck = false;
              buildType = "debug";
              dontStrip = true;

              cargoHash = "sha256-8Ba0utfeA2uKeB+SfSZPwusxiFGtRF3VmoO9+6CZ0O8=";
              # See: https://github.com/memflow/memflow-qemu/tree/next#building-the-stand-alone-connector-for-dynamic-loading
              cargoBuildFlags = [ "--workspace" "--all-features" ];

              meta = with lib; with cargoTOML.package; {
                inherit description homepage;
                downloadPage = https://github.com/memflow/memflow-qemu/releases;
                license = licenses.mit;
              };
            });

        };
      }
    );
}
