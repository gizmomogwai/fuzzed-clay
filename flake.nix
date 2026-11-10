{
  description = "Selector UI simulator in D, laid out with Clay and drawn with raylib";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Clay lives in the vendor/clay submodule; its API comes through ImportC (see source/clay_c.c).
    self.submodules = true;

    # Provides fuzzed.model and fuzzed.algorithm; only those two modules are compiled.
    fuzzed = {
      url = "github:gizmomogwai/fuzzed";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, fuzzed }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = function:
        nixpkgs.lib.genAttrs systems (system: function nixpkgs.legacyPackages.${system});
      # nixpkgs has only LDC 1.42.0; build 1.43.0 with nixpkgs' recipe and 1.42.0 as bootstrap compiler.
      ldc = pkgs:
        pkgs.ldc.overrideAttrs (old: {
          version = "1.43.0";
          src = pkgs.fetchFromGitHub {
            owner = "ldc-developers";
            repo = "ldc";
            tag = "v1.43.0";
            hash = "sha256-ZMYAg3WTTp09yVRSZEE+eRuVgEJSFUGHYM3u5Hfmo3o=";
            fetchSubmodules = true;
          };
          # The full LDC, druntime and Phobos test suites take far longer than the build.
          doCheck = false;
          # FindLLVM prefers versioned names like llvm-config-18, which can come from the host's /usr/bin.
          cmakeFlags = old.cmakeFlags ++ [ "-DLLVM_CONFIG=${pkgs.llvm_21.dev}/bin/llvm-config" ];
        });
      # nixpkgs' raylib pulls in GTK (glfw -> libdecor, for Wayland title bars) and pulseaudio.
      # The selector is a borderless X11 window without sound, so build both without them.
      raylib = pkgs:
        (if pkgs.stdenv.hostPlatform.isLinux then
          (pkgs.raylib.override {
            pulseSupport = false;
            glfw = pkgs.glfw.overrideAttrs (old: {
              # Drops the hard-coded libdecor and wayland library paths.
              postPatch = "";
              nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];
              buildInputs = with pkgs; [ libx11 libxrandr libxinerama libxcursor libxi libxext libxxf86vm ];
              cmakeFlags = old.cmakeFlags ++ [ (pkgs.lib.cmakeBool "GLFW_BUILD_WAYLAND" false) ];
            });
          }).overrideAttrs {
            # Without libGLU, CMake's FindOpenGL no longer links it; raylib calls no GLU function.
            propagatedBuildInputs = [ pkgs.libx11 pkgs.libxrandr ];
          }
        else
          pkgs.raylib).overrideAttrs (old: {
            # raylib saves a screenshot on F12 by default; F12 toggles Clay's debug view instead.
            cmakeFlags = old.cmakeFlags ++ [ (pkgs.lib.cmakeBool "SUPPORT_SCREEN_CAPTURE" false) ];
          });
    in {
      packages = forAllSystems (pkgs: rec {
        # The selector executable, built by dub; dub-lock.json is generated with `nix run nixpkgs#dub-to-nix`.
        clay-selector = pkgs.buildDubPackage {
          pname = "clay-selector";
          version = self.shortRev or "dirty";
          src = self;
          dubLock = ./dub-lock.json;
          compiler = ldc pkgs;
          dubBuildFlags = [ "--config=application" ];
          buildInputs = [ (raylib pkgs) pkgs.stb ];
          nativeBuildInputs = [ pkgs.removeReferencesTo ];
          # fuzzed is a local path dependency for development; point it at the flake input.
          postPatch = ''
            cp -r ${fuzzed} fuzzed-src
            chmod -R u+w fuzzed-src
            substituteInPlace dub.sdl dub.selections.json \
              --replace-fail "../14-fuzzed" "$PWD/fuzzed-src"
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 out/main/clay-selector/clay-selector -t $out/bin
            # Phobos names libcurl for std.net.curl, which the selector never uses; curl and its TLS stack cost ~25 MB.
            remove-references-to -t ${pkgs.curl.out} $out/bin/clay-selector
            runHook postInstall
          '';
          disallowedReferences = [ pkgs.curl.out ];
          meta.mainProgram = "clay-selector";
        };
        default = clay-selector;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.clay-selector}/bin/clay-selector";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ (ldc pkgs) pkgs.dub (raylib pkgs) pkgs.stb ];
        };
      });
    };
}
