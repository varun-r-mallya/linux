#!/usr/bin/env bash
# Mirror the default branch (HEAD) of every upstream in mirrors.conf into a
# branch of this repository.
#
# usage: sync-mirrors.sh <this-repo-url> <mirrors.conf>
#
# Downloads as little as possible:
#  - Tips are compared with ls-remote first. Mirrors that are already up to
#    date are skipped, and if nothing moved nothing is fetched at all.
#  - Otherwise a scratch repo is seeded from this repository with the last
#    $SEED_WINDOW of history of the mirrored branches, and the upstreams are
#    fetched with the same window. Linux trees share nearly all of their
#    history, so an upstream only sends the commits that none of the other
#    mirrors already have - a brand-new mirror (e.g. kvm) only pulls its own
#    commits from kernel.org instead of the entire kernel history.
#  - The pushes are checked by the receiving side, which refuses a shallow
#    push unless it already has all of the history behind it. If that happens
#    (or anything else fails), everything is redone once with full history.
#    Set SEED_WINDOW= (empty) to always use full history.
set -euo pipefail

self=$1
conf=$2
window=${SEED_WINDOW-6 months ago}

die() { echo "::error::$*"; exit 1; }

urls=() branches=()
while read -r url branch _ || [[ -n $url ]]; do
	url=${url%$'\r'} branch=${branch%$'\r'}
	[[ -z $url || $url == \#* ]] && continue
	[[ -n $branch ]] || die "$conf: no branch given for $url"
	git check-ref-format --branch "$branch" >/dev/null ||
		die "$conf: invalid branch name '$branch'"
	[[ $branch != automation ]] || die "$conf: refusing to overwrite 'automation'"
	for b in "${branches[@]}"; do
		[[ $b != "$branch" ]] || die "$conf: branch '$branch' listed twice"
	done
	urls+=("$url") branches+=("$branch")
done < "$conf"
((${#urls[@]})) || die "$conf: no mirrors configured"

declare -A mirror
heads=$(git ls-remote --heads "$self")
while read -r sha ref; do
	[[ -n $ref ]] && mirror[${ref#refs/heads/}]=$sha
done <<< "$heads"

todo=()
for i in "${!urls[@]}"; do
	tip=$(git ls-remote "${urls[i]}" HEAD)
	tip=${tip%%$'\t'*}
	[[ -n $tip ]] || die "cannot resolve HEAD of ${urls[i]}"
	if [[ ${mirror[${branches[i]}]:-} == "$tip" ]]; then
		echo "${branches[i]}: up to date at $tip"
	else
		echo "${branches[i]}: ${mirror[${branches[i]}]:-(new)} -> $tip"
		todo+=("$i")
	fi
done
((${#todo[@]})) || { echo "Nothing to do."; exit 0; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
declare -A synced

# sync <shallow|full>: bring every pending mirror up to date, starting from an
# empty scratch repo. Returns non-zero on the first failure.
sync() {
	local mode=$1 depth=() b i ok out
	[[ $mode == shallow ]] && depth=(--shallow-since="$window")

	rm -rf "$work/repo"
	git init -q --bare "$work/repo"
	git -C "$work/repo" config gc.auto 0

	# Seed with every branch we already mirror, one at a time so that a
	# single branch that can't be seeded (e.g. its tip is older than the
	# window) doesn't take the others down with it.
	for b in "${branches[@]}"; do
		[[ -n ${mirror[$b]:-} ]] || continue
		echo "::group::[$mode] seed $b"
		git -C "$work/repo" fetch -q "${depth[@]}" "$self" \
			"+refs/heads/$b:refs/remotes/self/$b" ||
			echo "::warning::could not seed $b, continuing without it"
		echo "::endgroup::"
	done

	for i in "${todo[@]}"; do
		b=${branches[i]}
		[[ -z ${synced[$b]:-} ]] || continue
		echo "::group::[$mode] ${urls[i]} -> $b"
		# Fetch into a ref (not just FETCH_HEAD) so that the following
		# upstream fetches can offer these commits as haves too.
		git -C "$work/repo" fetch -q "${depth[@]}" "${urls[i]}" \
			"+HEAD:refs/upstream/$b" || return 1
		ok=0
		for attempt in 1 2 3; do
			if out=$(git -C "$work/repo" -c http.postBuffer=1048576000 \
				-c http.version=HTTP/1.1 push --porcelain \
				--force-with-lease="refs/heads/$b:${mirror[$b]:-}" \
				"$self" "refs/upstream/$b:refs/heads/$b" 2>&1); then
				ok=1
				break
			fi
			echo "$out"
			# Refused for lack of history: retrying won't help.
			[[ $out != *shallow* ]] || return 1
			echo "push attempt $attempt failed, retrying..."
			sleep 10
		done
		((ok)) || return 1
		echo "$out"
		synced[$b]=1
		echo "::endgroup::"
	done
}

if [[ -n $window ]] && sync shallow; then
	exit 0
fi
[[ -z $window ]] || echo "::warning::shallow sync failed, retrying with full history"
sync full || die "sync failed"
