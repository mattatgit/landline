{
  description = "Landline desktop application and development environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, rust-overlay, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      systemContext = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          rust = pkgs.rust-bin.stable."1.91.0".default;
          rustPlatform = pkgs.makeRustPlatform {
            cargo = rust;
            rustc = rust;
          };
          landlineFonts = pkgs.google-fonts.override { fonts = [ "Inter" "Inter Tight" ]; };
          runtimeLibs = with pkgs; [
            alsa-lib
            libGL
            libxkbcommon
            wayland
            libx11
            libxcursor
            libxi
            libxrandr
          ];
          landline = rustPlatform.buildRustPackage {
            pname = "landline";
            version = "0.1.0-preview";
            src = ./LandlineNix;

            cargoLock.lockFile = ./LandlineNix/Cargo.lock;

            nativeBuildInputs = [
              pkgs.pkg-config
              pkgs.makeWrapper
            ];

            buildInputs = runtimeLibs;

            LANDLINE_FONT_DIR = "${landlineFonts}/share/fonts/truetype";

            postInstall = ''
              mv "$out/bin/landline-nix" "$out/bin/.landline-nix-unwrapped"
              makeWrapper "$out/bin/.landline-nix-unwrapped" "$out/bin/landline" \
                --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"

              mkdir -p "$out/share/applications"
              cat > "$out/share/applications/landline.desktop" <<'DESKTOP'
              [Desktop Entry]
              Type=Application
              Name=Landline
              Comment=Peer-to-peer push-to-talk
              Exec=landline
              Terminal=false
              Categories=Network;AudioVideo;Audio;
              StartupNotify=true
              DESKTOP
            '';

            meta = {
              description = "Peer-to-peer push-to-talk desktop application";
              homepage = "https://github.com/mattatgit/landline";
              license = pkgs.lib.licenses.gpl3Plus;
              mainProgram = "landline";
              platforms = pkgs.lib.platforms.linux;
            };
          };
        in {
          inherit pkgs rust rustPlatform landlineFonts runtimeLibs landline;
        };
    in {
      packages = forAllSystems (system:
        let ctx = systemContext system;
        in {
          default = ctx.landline;
          landline = ctx.landline;
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.landline}/bin/landline";
        };
        landline = {
          type = "app";
          program = "${self.packages.${system}.landline}/bin/landline";
        };
      });

      devShells = forAllSystems (system:
        let ctx = systemContext system;
        in {
          default = ctx.pkgs.mkShell {
            packages = [
              ctx.rust
              ctx.pkgs.pkg-config
              ctx.pkgs.alsa-lib
              ctx.pkgs.libxkbcommon
              ctx.pkgs.wayland
              ctx.pkgs.libx11
              ctx.pkgs.libxcursor
              ctx.pkgs.libxi
              ctx.pkgs.libxrandr
              ctx.pkgs.libGL
              ctx.landlineFonts
            ];

            LD_LIBRARY_PATH = ctx.pkgs.lib.makeLibraryPath ctx.runtimeLibs;
            LANDLINE_FONT_DIR = "${ctx.landlineFonts}/share/fonts/truetype";
            RUST_BACKTRACE = "1";
          };
        });
    };
}
