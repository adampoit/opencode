# Fork Release Sync and Nix Cache Setup

This setup keeps a private fork branch synced with upstream `anomalyco/opencode` releases, auto-merges clean sync PRs, and tags a reviewer when manual intervention is needed.

## 1) Create your long-lived fork branch

Use a branch that carries your private changes (example: `private/dev`).

## 2) Add repository variables

In your fork, configure these repository variables:

- `FORK_SYNC_BASE_BRANCH`: target branch in your fork (for example `private/dev`)
- `FORK_SYNC_UPSTREAM_REPO`: upstream repo (default: `anomalyco/opencode`)
- `FORK_SYNC_REVIEWER`: GitHub username to request review from when automation cannot complete (without `@`)
- `CACHIX_CACHE`: optional Cachix cache name for Nix artifacts (recommended for faster local installs)

## 3) Add repository secrets

- `CACHIX_AUTH_TOKEN`: optional; required only if you want to push build outputs to Cachix

## 4) Enable repository settings

- Enable **Allow auto-merge** in repository settings.
- Add branch protection rules for `FORK_SYNC_BASE_BRANCH` and require CI checks you care about (for example `test`, `nix-eval`).

With this in place:

- `.github/workflows/fork-sync-upstream-release.yml` creates a PR from each new upstream release tag.
- It enables auto-merge when checks pass.
- `.github/workflows/fork-sync-watchdog.yml` requests your review if conflicts or failing checks block the sync.
- `.github/workflows/fork-nix-cache.yml` uses Magic Nix Cache to speed up CI and can optionally push to Cachix.

## 5) Nix-darwin and home-manager cache usage

If you configure Cachix, add your cache to your nix-darwin flake:

```nix
{
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://<your-cache>.cachix.org"
    ];

    trusted-public-keys = [
      "<your-cache>.cachix.org-1:<public-key>"
    ];
  };
}
```

You can get the public key with:

```bash
cachix use <your-cache>
```

Magic Nix Cache still helps CI even without Cachix configured.
