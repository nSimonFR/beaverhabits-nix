# BeaverHabits — self-hosted habit tracker (daya0576/beaverhabits).
#
# Python / NiceGUI app, uv-managed. Built with uv2nix directly from the upstream
# uv.lock — nixpkgs' nicegui is too old (3.1 vs required >=3.13) and fastapi-users
# is absent, so the usual python3Packages route is a non-starter.
#
# Runtime shape: a single gunicorn process with one uvicorn worker (upstream's
# start.sh runs `-w 1` so socket.io connections stay on one worker). SQLite via
# aiosqlite (pure-Python; no patchelf). No browser/ML deps.
#
# Two upstream facts drive the packaging:
#   1. Version is `dynamic` via `uv-dynamic-versioning`, which shells out to git.
#      A store-path source has no .git, and uv-dynamic-versioning is in neither
#      nixpkgs nor pyproject-build-systems — so we patch pyproject.toml to a
#      static version and drop that build backend (hatchling alone suffices).
#   2. Static assets are mounted with a RELATIVE path — `app.add_static_files(
#      "/statics", "statics")` in beaverhabits/routes/routes.py — so the server
#      must run with a cwd that contains `statics/`. We ship it and chdir there.
{
  lib,
  stdenv,
  stdenvNoCC,
  callPackage,
  fetchFromGitHub,
  python312,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:

let
  version = "0.9.1";

  rawSrc = fetchFromGitHub {
    owner = "daya0576";
    repo = "beaverhabits";
    rev = "v${version}";
    hash = "sha256-5XIAKn08L2fm75L0tP72SZARjTQWMR31ne6RPNy1aVY=";
  };

  # Patch out uv-dynamic-versioning: pin a static version and reduce the build
  # backend to plain hatchling. Done on the source BEFORE uv2nix loads the
  # workspace, since the loader reads pyproject.toml to derive build systems.
  src = stdenvNoCC.mkDerivation {
    pname = "beaverhabits-src";
    inherit version;
    src = rawSrc;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      cp -r . $out
      substituteInPlace $out/pyproject.toml \
        --replace-fail 'dynamic = ["version"]' 'version = "${version}"' \
        --replace-fail 'requires = ["hatchling", "uv-dynamic-versioning"]' 'requires = ["hatchling"]' \
        --replace-fail '[tool.hatch.version]' '[tool.hatch.version_disabled]'
    '';
  };

  python = python312;

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };

  # Prefer prebuilt wheels — far fewer native build headaches on aarch64.
  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  pythonSet =
    (callPackage pyproject-nix.build.packages { inherit python; }).overrideScope
      (lib.composeManyExtensions [
        pyproject-build-systems.overlays.default
        overlay
      ]);

  # Production virtualenv containing beaverhabits + its default (non-dev) deps.
  # gunicorn / uvicorn-worker are declared as runtime deps upstream, so they land
  # in the venv's bin/.
  venv = pythonSet.mkVirtualEnv "beaverhabits-env" workspace.deps.default;

in
stdenv.mkDerivation {
  pname = "beaverhabits";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Ship the source tree (statics/ + the package) and run gunicorn from it so
    # the relative "statics" mount resolves. beaverhabits itself is also in the
    # venv, but importing from cwd here keeps runtime paths self-consistent.
    mkdir -p $out/share/beaverhabits
    cp -r beaverhabits statics $out/share/beaverhabits/

    mkdir -p $out/bin
    # --no-control-socket: gunicorn 25.x otherwise creates a runtime control
    # socket at a cwd-relative path; cwd here is the read-only store dir (needed
    # for the relative "statics" mount), so it logs a non-fatal "Control server
    # error: Read-only file system" on every start. We don't use runtime control.
    cat > $out/bin/beaverhabits <<EOF
    #!${stdenv.shell}
    set -e
    cd $out/share/beaverhabits
    exec ${venv}/bin/gunicorn beaverhabits.main:app \
      -k uvicorn_worker.UvicornWorker -w 1 --max-requests 10000 \
      --no-control-socket \
      --bind "\''${HOST:-127.0.0.1}:\''${PORT:-13342}"
    EOF
    chmod +x $out/bin/beaverhabits

    runHook postInstall
  '';

  passthru = { inherit venv python; };

  meta = with lib; {
    description = "Self-hosted habit tracker (NiceGUI)";
    homepage = "https://github.com/daya0576/beaverhabits";
    license = licenses.bsd3;
    platforms = platforms.linux;
    mainProgram = "beaverhabits";
  };
}
