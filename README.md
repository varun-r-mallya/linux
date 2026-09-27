```
Automation
------------------------------------------------------------------------------
This default automation branch syncs everything from git.kernel.org as required and set up.

Each line of .github/mirrors.conf is "<upstream-url> <branch>": the upstream's
default branch (HEAD) is mirrored, commit for commit, into <branch> of this
repository twice a day (or on demand via "Run workflow"). Add a line to add a
mirror; the branch is created on the next run.

The sync is done by .github/scripts/sync-mirrors.sh and downloads as little as
possible: mirrors whose tips haven't moved are skipped without fetching
anything, and the rest are fetched on top of the last 6 months of the already
mirrored branches, so an upstream only sends commits that no other mirror has
yet. If GitHub needs older history than that to accept a push, the run falls
back to full history by itself.
```
