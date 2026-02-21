# Fork Release Sync and Nix Cache Setup

This setup keeps a private fork branch synced with upstream `anomalyco/opencode` releases, auto-merges clean sync PRs, and tags a reviewer when manual intervention is needed.

## 1) Pick your integration branch

Use your fork `dev` branch as the integration branch.

This fork setup assumes `dev` for required checks and branch protection.

## 2) Add repository variables

In your fork, configure these repository variables:

- `FORK_SYNC_UPSTREAM_REPO`: upstream repo (default: `anomalyco/opencode`)
- `FORK_SYNC_REVIEWER`: GitHub username to request review from when automation cannot complete (without `@`)
- `CACHIX_CACHE`: optional Cachix cache name for Nix artifacts (recommended for faster local installs)

## 3) Add repository secrets

- `FORK_SYNC_TOKEN`: recommended; a PAT with `repo` scope used by sync automation so PR events trigger normal CI checks
- `CACHIX_AUTH_TOKEN`: optional; required only if you want to push build outputs to Cachix

Without `FORK_SYNC_TOKEN`, the workflow falls back to `GITHUB_TOKEN`. In that mode, the sync PR is created, but downstream `pull_request` workflows may not trigger automatically.

## 4) Enable repository settings

- Enable **Allow auto-merge** in repository settings.
- Add branch protection rules for `dev` and require CI checks you care about (for example `test`, `nix-eval`).

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

## 6) Working model: fork integration vs upstream contributions

Use two long-lived bases with different purposes:

- `origin/dev`: your fork integration branch (upstream release sync PRs + your merged feature work)
- `upstream/dev`: the clean base for PRs you want to send to `anomalyco/opencode`

### Day-to-day fork development

Create feature branches from `origin/dev`, then merge them back into `origin/dev`.

```bash
git fetch origin upstream
git switch dev
git reset --hard origin/dev
git switch -c feat/my-change
```

This keeps your feature work compatible with your fork's required checks and release-sync automation.

### Preparing an upstream PR without cherry-picking

When a feature branch (based on `origin/dev`) is ready to propose upstream, create an upstream-ready copy and rebase the whole feature stack onto `upstream/dev`.

```bash
git fetch origin upstream
git switch -c feat/my-change-upstream feat/my-change
BASE=$(git merge-base --fork-point origin/dev feat/my-change || git merge-base origin/dev feat/my-change)
git rebase --onto upstream/dev "$BASE" feat/my-change-upstream
git push -u origin feat/my-change-upstream
```

Open your upstream PR from `adampoit:feat/my-change-upstream` to `anomalyco/opencode:dev`.

Notes:

- This rebases the branch in one operation; no per-commit cherry-picking is needed.
- Keep your original `feat/my-change` branch unchanged for fork-only CI/review if needed.
- If `upstream/dev` moves while the PR is open, rebase `feat/my-change-upstream` onto latest `upstream/dev` and force-push with lease:

```bash
git fetch upstream
git switch feat/my-change-upstream
git rebase upstream/dev
git push --force-with-lease
```
