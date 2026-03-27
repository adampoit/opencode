Vendored from `randymarsh77/static-nix-cache` at commit `7e5e0f2e1ce2e252c5bd173122d069a139edbd51`.

Local changes:

- cache GitHub release assets in memory to avoid repeated asset-list API scans
- retry GitHub release requests and uploads with backoff
- log server-side route errors with more detail
