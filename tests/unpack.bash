# shellcheck shell=bash

up_setup() {
  ug_mktemp_dir
  UP_HOME=$UG_TMPDIR/box/home
  UP_REPO=$UG_TMPDIR/repo
  mkdir -p "$UP_HOME" "$UP_REPO" || fail 'cannot make the scratch home and repo'
  render "$UG_REPO_ROOT/host/agent/agent-unpack" "$UG_TMPDIR/agent-unpack" AGENT_HOME="$UP_HOME"
  chmod +x "$UG_TMPDIR/agent-unpack" || fail 'cannot make agent-unpack executable'
  up_git init -q || fail 'cannot init the scratch repo'
}

up_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$UP_REPO" \
    -c user.name=ug -c user.email=ug@example.invalid -c commit.gpgsign=false "$@"
}

up_put() {
  mkdir -p "$(dirname "$UP_REPO/$1")" && printf '%s\n' "$2" >"$UP_REPO/$1" || fail "cannot write $1"
}

up_commit() {
  up_git add -A && up_git commit -q -m "$1" || fail "cannot commit $1"
  up_git archive --format=tar HEAD >"$UG_TMPDIR/$1.tar" || fail "cannot archive $1"
}

unpack() {
  up_rc=0
  "$UG_TMPDIR/agent-unpack" "$1" <"$2" 2>"$UG_TMPDIR/err" || up_rc=$?
  up_err=$(cat "$UG_TMPDIR/err")
}

up_names() {
  (cd "$1" && find . -mindepth 1 ! -name .ug-names -print | LC_ALL=C sort)
}

up_lines() {
  printf '%s\n' "$@"
}

t_2_1() {
  up_setup
  up_put README.md 'agent readme'
  up_put bin/tool 'echo tool'
  up_commit first
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "first unpack exits 0 ($up_err)"
  assert_eq "$(up_lines ./README.md ./bin ./bin/tool)" "$(up_names "$UP_HOME/apps/alpha")" \
    'the target holds exactly the files of the commit'
  assert_eq 'agent readme' "$(cat "$UP_HOME/apps/alpha/README.md")" 'README.md has the committed content'
  assert_eq 'echo tool' "$(cat "$UP_HOME/apps/alpha/bin/tool")" 'bin/tool has the committed content'
}

t_2_2() {
  up_setup
  up_put a.txt 'a one'
  up_put b.txt 'b one'
  up_put lib/c.txt 'c one'
  up_commit first
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "first unpack exits 0 ($up_err)"
  assert_eq "$(up_lines ./a.txt ./b.txt ./lib ./lib/c.txt)" "$(up_names "$UP_HOME/apps/alpha")" \
    'the first commit is unpacked'
  up_git rm -q b.txt || fail 'cannot remove b.txt'
  up_put a.txt 'a two'
  up_put lib/c.txt 'c two'
  up_commit second
  unpack apps/alpha "$UG_TMPDIR/second.tar"
  assert_eq 0 "$up_rc" "second unpack exits 0 ($up_err)"
  assert_eq "$(up_lines ./a.txt ./lib ./lib/c.txt)" "$(up_names "$UP_HOME/apps/alpha")" \
    'b.txt removed by the second commit is gone from the target'
  assert_eq 'a two' "$(cat "$UP_HOME/apps/alpha/a.txt")" 'a.txt has the new content'
  assert_eq 'c two' "$(cat "$UP_HOME/apps/alpha/lib/c.txt")" 'lib/c.txt has the new content'
}

t_2_3() {
  local dest
  up_setup
  dest=$UP_HOME/apps/alpha
  mkdir -p "$dest/notes" || fail 'cannot seed the target'
  printf 'agent memory\n' >"$dest/MEMORY.md"
  printf 'agent note\n' >"$dest/notes/today.md"
  up_put a.txt 'a one'
  up_put b.txt 'b one'
  up_commit first
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "first unpack exits 0 ($up_err)"
  up_git rm -q b.txt || fail 'cannot remove b.txt'
  up_commit second
  unpack apps/alpha "$UG_TMPDIR/second.tar"
  assert_eq 0 "$up_rc" "second unpack exits 0 ($up_err)"
  assert_eq "$(up_lines ./MEMORY.md ./a.txt ./notes ./notes/today.md)" "$(up_names "$dest")" \
    'the seeded agent files stay next to the unpacked files'
  assert_eq 'agent memory' "$(cat "$dest/MEMORY.md")" 'MEMORY.md keeps its content'
  assert_eq 'agent note' "$(cat "$dest/notes/today.md")" 'notes/today.md keeps its content'
}

t_2_4() {
  local listing
  up_setup
  up_put .gitignore 'scratch/'
  up_put .claude-plugin/plugin.json '{"name":"alpha"}'
  up_put README.md 'agent readme'
  up_commit first
  listing=$(tar -tf "$UG_TMPDIR/first.tar") || fail 'cannot list the archive'
  assert_contains $'\n.gitignore\n' $'\n'"$listing"$'\n' 'the archive lists .gitignore'
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "unpack exits 0 ($up_err)"
  assert_eq "$(up_lines ./.claude-plugin ./.claude-plugin/plugin.json ./README.md)" \
    "$(up_names "$UP_HOME/apps/alpha")" '.claude-plugin is copied and .gitignore is not'
  assert_eq '{"name":"alpha"}' "$(cat "$UP_HOME/apps/alpha/.claude-plugin/plugin.json")" \
    '.claude-plugin/plugin.json has the committed content'
}

t_2_5() {
  local before empty_tree
  up_setup
  up_put a.txt 'a one'
  up_commit first
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "a non-empty archive is unpacked ($up_err)"
  before=$(tree_digest "$UP_HOME/apps/alpha")
  empty_tree=$(up_git mktree </dev/null) || fail 'cannot make an empty tree'
  up_git archive --format=tar "$empty_tree" >"$UG_TMPDIR/empty.tar" || fail 'cannot archive the empty tree'
  unpack apps/alpha "$UG_TMPDIR/empty.tar"
  [[ $up_rc != 0 ]] || fail 'an empty archive exits 0'
  assert_contains 'empty archive' "$up_err" 'stderr says the archive is empty'
  assert_eq "$before" "$(tree_digest "$UP_HOME/apps/alpha")" 'an empty archive leaves the target unchanged'
}

t_2_6() {
  local before size
  up_setup
  up_put a.txt 'a one'
  up_put b.txt 'b one'
  up_commit first
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "the whole archive is unpacked ($up_err)"
  up_put a.txt 'a two'
  head -c 20000 /dev/zero | tr '\0' x >"$UP_REPO/b.txt"
  up_commit second
  before=$(tree_digest "$UP_HOME/apps/alpha")
  size=$(wc -c <"$UG_TMPDIR/second.tar") || fail 'cannot size the archive'
  head -c $((size / 2)) "$UG_TMPDIR/second.tar" >"$UG_TMPDIR/damaged.tar"
  unpack apps/alpha "$UG_TMPDIR/damaged.tar"
  [[ $up_rc != 0 ]] || fail 'a damaged archive exits 0'
  assert_eq "$before" "$(tree_digest "$UP_HOME/apps/alpha")" 'a damaged archive leaves the target unchanged'
}

t_2_7() {
  local before target
  up_setup
  up_put a.txt 'a one'
  up_commit first
  before=$(tree_digest "$UG_TMPDIR/box")
  for target in .. ../escape apps/../../escape /tmp/escape "$UG_TMPDIR/box/escape"; do
    unpack "$target" "$UG_TMPDIR/first.tar"
    assert_eq 1 "$up_rc" "target $target is refused"
    assert_contains "refused target $target" "$up_err" "stderr names the refused target $target"
    assert_eq "$before" "$(tree_digest "$UG_TMPDIR/box")" "target $target creates nothing"
  done
  unpack apps/alpha "$UG_TMPDIR/first.tar"
  assert_eq 0 "$up_rc" "the good target apps/alpha is unpacked ($up_err)"
  assert_eq 'a one' "$(cat "$UP_HOME/apps/alpha/a.txt")" 'the good target gets the committed file'
}
