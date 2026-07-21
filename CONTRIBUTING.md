# Contributing

Please open an issue before proposing a new module or distribution-specific change.

Every change must preserve dry-run behavior, backups, rollback, quoted paths, and clear error handling. Never add remote execution, broad deletion, or privileged commands without an allowlisted target and an explicit confirmation path.

Before opening a pull request, run `bash -n adhyper-linux.sh` and `shellcheck adhyper-linux.sh` on a supported Linux distribution. State the distribution, shell version, and rollback test in the pull request.
