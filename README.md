# automation

This is the default branch of this repo and holds only repo automation
(GitHub Actions workflows). It is intentionally kept separate from
`master`, which is a pristine, force-synced mirror of
[git.kernel.org bpf/bpf-next](https://git.kernel.org/pub/scm/linux/kernel/git/bpf/bpf-next.git).

`master` is never touched by anything other than the mirror workflow, so
its history always matches upstream exactly, commit-for-commit.
