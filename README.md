# beaverhabits-nix

Nix packaging for [BeaverHabits](https://github.com/daya0576/beaverhabits) — a
self-hosted habit tracker (Python / NiceGUI). Same model as
[`airtrail-nix`](https://github.com/nSimonFR/airtrail-nix) /
[`sure-nix`](https://github.com/nSimonFR/sure-nix): a `packages.default`
derivation plus a NixOS module, no containers.

The app is built with [uv2nix](https://github.com/pyproject-nix/uv2nix) straight
from upstream's `uv.lock`, because nixpkgs' `nicegui` is too old (3.1 vs the
required ≥3.13) and `fastapi-users` is absent.

## Usage

```nix
{
  inputs.beaverhabits-nix.url = "github:nSimonFR/beaverhabits-nix";

  # in your NixOS configuration:
  imports = [ inputs.beaverhabits-nix.nixosModules.beaverhabits ];

  services.beaverhabits = {
    enable = true;
    port = 13342;
    environmentFile = "/run/agenix/beaverhabits-env";  # signing secrets
    settings.APP_URL = "https://habits.example.ts.net";
  };
}
```

`environmentFile` should export the three secrets BeaverHabits signs with (random
values; rotating them logs everyone out / invalidates reset tokens):

```
NICEGUI_STORAGE_SECRET=...
JWT_SECRET=...
RESET_PASSWORD_TOKEN_SECRET=...
```

Storage is a single SQLite database (`HABITS_STORAGE=DATABASE`, default
`${stateDir}/habits.db`) — no external database. SQLAlchemy creates the schema on
first start; there is no migration step.

## Packaging notes

- **Static version**: upstream derives its version from git tags via
  `uv-dynamic-versioning`, which isn't in nixpkgs/pyproject-build-systems and
  needs a `.git`. `package.nix` patches `pyproject.toml` to a static version and
  reduces the build backend to plain `hatchling`.
- **Relative static mount**: `beaverhabits/routes/routes.py` mounts assets with
  `app.add_static_files("/statics", "statics")` — a path relative to the process
  cwd. The wrapper ships `statics/` and `chdir`s into it before exec'ing gunicorn.
- Runs a single gunicorn + uvicorn worker (`-w 1`), mirroring upstream `start.sh`.
