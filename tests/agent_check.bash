# shellcheck shell=bash

ac_setup() {
  ug_mktemp_dir
  AC_HOME=$UG_TMPDIR/home
  AC_STUBS=$UG_TMPDIR/stubs
  AC_REQ=$UG_TMPDIR/requirements
  AC_CALLS=$UG_TMPDIR/omp.calls
  mkdir -p "$AC_HOME" "$AC_STUBS" || fail 'cannot make the scratch home and stubs'
  ac_settings '{}'
}

ac_settings() {
  printf '%s\n' "$1" >"$UG_TMPDIR/settings.json" || fail 'cannot write the stub settings'
  ac_omp "[[ \$* == 'config list --json' ]] || exit 3
cat '$UG_TMPDIR/settings.json'"
}

ac_omp() {
  printf '#!/bin/bash\nprintf '\''%%s\\n'\'' "$*" >>'\''%s'\''\n%s\n' "$AC_CALLS" "$1" >"$AC_STUBS/omp" &&
    chmod +x "$AC_STUBS/omp" || fail 'cannot write the omp stub'
}

ac_requirements() {
  printf '%s\n' "$@" >"$AC_REQ" || fail 'cannot write the requirements'
}

ac_run() {
  local check=${AC_CHECK:-$UG_REPO_ROOT/host/agent/agent-check}
  ac_rc=0
  env -i HOME="$AC_HOME" PATH="$AC_STUBS:/usr/bin:/bin" "$check" "$@" >"$UG_TMPDIR/out" 2>"$UG_TMPDIR/err" || ac_rc=$?
  ac_out=$(cat "$UG_TMPDIR/out")
  ac_err=$(cat "$UG_TMPDIR/err")
}

t_8_1() {
  ac_setup
  ac_requirements \
    'setting memory.backend=mnemopi: the dream reads mnemopi' \
    'setting mnemopi.autoRetain=false: the dream retains on purpose' \
    'setting tools.maxTimeout=0: tools may run long' \
    'file .omp/agent/extensions/guard.ts: it blocks deletes'
  ac_settings '{"memory.backend":{"value":"mnemopi","type":"enum"},"mnemopi.autoRetain":{"value":false,"type":"boolean"},"tools.maxTimeout":{"value":0,"type":"number"}}'
  mkdir -p "$AC_HOME/.omp/agent/extensions" && : >"$AC_HOME/.omp/agent/extensions/guard.ts" || fail 'cannot write the guard file'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 when all requirements are met ($ac_err)"
  assert_eq '' "$ac_out" 'agent-check prints nothing when all requirements are met'
}

t_8_2() {
  ac_setup
  ac_requirements \
    'setting memory.backend=mnemopi: the dream reads mnemopi' \
    'setting mnemopi.noEmbeddings=true: recall uses full-text search' \
    'setting mnemopi.dbPath=/db: the dream copies it' \
    'setting gone.key=on: an old omp had it'
  ac_settings '{"memory.backend":{"value":"off","type":"enum"},"mnemopi.noEmbeddings":{"value":false,"type":"boolean"},"mnemopi.dbPath":{"type":"string"}}'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 when settings are unmet ($ac_err)"
  assert_eq "memory.backend is off; underground needs mnemopi: the dream reads mnemopi. set it in your agent-config config.yml
mnemopi.noEmbeddings is false; underground needs true: recall uses full-text search. set it in your agent-config config.yml
mnemopi.dbPath is unset; underground needs /db: the dream copies it. set it in your agent-config config.yml
gone.key is not a setting of this omp; underground needs on: an old omp had it. update omp" "$ac_out" \
    'agent-check prints one warning per unmet setting: a wrong value, an unset value and an unknown key'
}

t_8_3() {
  ac_setup
  ac_requirements \
    'file .omp/agent/skills/dream-review/SKILL.md: the dream follows it' \
    'file .omp/agent/extensions/guard.ts: it blocks deletes'
  mkdir -p "$AC_HOME/.omp/agent/extensions" && : >"$AC_HOME/.omp/agent/extensions/guard.ts" || fail 'cannot write the guard file'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 when a file is missing ($ac_err)"
  assert_eq '~/.omp/agent/skills/dream-review/SKILL.md is missing; underground needs it: the dream follows it. add it to your agent-config' \
    "$ac_out" 'agent-check warns about the missing file only'
}

t_8_4() {
  ac_setup
  ac_requirements \
    'setting memory.backend=mnemopi: the dream reads mnemopi' \
    'setting mnemopi.scoping=global: the dream reads one bank'
  rm -f "$AC_STUBS/omp"
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 without omp ($ac_err)"
  assert_eq 'agent-check cannot read the omp settings (omp is not on PATH), so 2 settings that underground needs are not checked' \
    "$ac_out" 'agent-check prints one warning without omp'
  ac_omp 'exit 1'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 when omp config list fails ($ac_err)"
  assert_eq 'agent-check cannot read the omp settings (omp config list failed), so 2 settings that underground needs are not checked' \
    "$ac_out" 'agent-check prints one warning when omp config list fails'
  ac_settings 'Working...'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 when omp prints no json ($ac_err)"
  assert_eq 'agent-check cannot read the omp settings (omp printed settings that are not json), so 2 settings that underground needs are not checked' \
    "$ac_out" 'agent-check prints one warning when omp prints no json'
}

t_8_5() {
  ac_setup
  ac_requirements \
    'setting memory.backend=mnemopi: the dream reads mnemopi' \
    'setting mnemopi.scoping=global: the dream reads one bank' \
    'setting mnemopi.noEmbeddings=true: recall uses full-text search'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 ($ac_err)"
  assert_eq 'config list --json' "$(cat "$AC_CALLS")" 'agent-check calls omp once for all settings'
}

t_8_6() {
  ac_setup
  mkdir -p "$UG_TMPDIR/code/bin" || fail 'cannot make the code dir'
  cp "$UG_REPO_ROOT/host/agent/agent-check" "$UG_TMPDIR/code/bin/agent-check" || fail 'cannot copy agent-check'
  printf '%s\n' 'file .omp/agent/marker: the default file is read' >"$UG_TMPDIR/code/bin/requirements" ||
    fail 'cannot write the default requirements'
  AC_CHECK=$UG_TMPDIR/code/bin/agent-check ac_run
  assert_eq 0 "$ac_rc" "agent-check without an argument exits 0 ($ac_err)"
  assert_eq '~/.omp/agent/marker is missing; underground needs it: the default file is read. add it to your agent-config' \
    "$ac_out" 'agent-check reads the requirements next to itself by default'
  AC_CHECK=$UG_TMPDIR/code/bin/agent-check ac_run a b
  assert_eq 64 "$ac_rc" 'agent-check with two arguments is a usage error'
  ac_run "$UG_TMPDIR/none"
  assert_eq 1 "$ac_rc" 'agent-check with a requirements file that does not exist fails'
  assert_contains "cannot read the requirements file $UG_TMPDIR/none" "$ac_err" 'agent-check names the missing requirements file'
}

t_8_7() {
  local want
  ac_setup
  ac_run "$UG_REPO_ROOT/host/requirements"
  assert_eq 0 "$ac_rc" "agent-check exits 0 on host/requirements ($ac_err)"
  [[ $ac_out != *'cannot read this line'* ]] || fail "host/requirements has a line that agent-check cannot read: $ac_out"
  [[ $ac_out != *autolearn* ]] || fail "host/requirements must not require autolearn, which lets the agent write unreviewed skills: $ac_out"
  for want in memory.backend=mnemopi mnemopi.scoping=global mnemopi.autoRetain=false mnemopi.noEmbeddings=true; do
    assert_contains "${want%%=*} is not a setting of this omp; underground needs ${want#*=}:" "$ac_out" \
      "host/requirements needs $want"
  done
  for want in .omp/agent/skills/dream-review/SKILL.md .omp/agent/extensions/underground-guard.ts; do
    assert_contains "~/$want is missing; underground needs it:" "$ac_out" "host/requirements needs the file $want"
  done
}

t_8_8() {
  ac_setup
  ac_requirements \
    'setting memory.backend mnemopi' \
    'setting mnemopi.noEmbeddings=true: recall uses full-text search'
  ac_settings '{"mnemopi.noEmbeddings":{"value":false,"type":"boolean"}}'
  ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 with a bad line ($ac_err)"
  assert_eq "agent-check cannot read this line of $AC_REQ: setting memory.backend mnemopi
mnemopi.noEmbeddings is false; underground needs true: recall uses full-text search. set it in your agent-config config.yml" \
    "$ac_out" 'agent-check warns about a bad line and still checks the others'
}

t_8_9() {
  ac_setup
  mkdir -p "$UG_TMPDIR/code/bin" || fail 'cannot make the code dir'
  cp "$UG_REPO_ROOT/host/agent/agent-check" "$UG_TMPDIR/code/bin/agent-check" || fail 'cannot copy agent-check'
  mv "$AC_STUBS/omp" "$UG_TMPDIR/code/bin/omp" || fail 'cannot move the omp stub next to agent-check'
  ac_requirements 'setting memory.backend=mnemopi: the dream reads mnemopi'
  AC_CHECK=$UG_TMPDIR/code/bin/agent-check ac_run "$AC_REQ"
  assert_eq 0 "$ac_rc" "agent-check exits 0 ($ac_err)"
  assert_eq 'memory.backend is not a setting of this omp; underground needs mnemopi: the dream reads mnemopi. update omp' \
    "$ac_out" 'agent-check finds the omp next to itself when omp is not on PATH'
}
