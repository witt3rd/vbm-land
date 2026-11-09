# lib/paths.sh: every path the tool uses inside a consumer repository, defined ONCE. Sourced, never run. Paths are relative to the consumer's root.
LAND_DIR=scripts/land                    # the vendored tool folder
LAND_PIN=$LAND_DIR/PIN                   # version, commit and checksum of the vendored tool
LAND_MANIFEST_FILE=$LAND_DIR/MANIFEST.sha256   # the per-file checksum list of the vendored tool
LAND_CONF_FILE=scripts/land.conf         # the repository's own settings
LAND_HOOKS_DEFAULT=scripts/land.d        # the repository's own hooks
LAND_SIGNERS_FILE=scripts/land.signers   # who may sign releases
LAND_ENTRY=scripts/land-direct           # the entry script an agent runs
LAND_SKILLS_DIR=.agents/skills           # where the tool's agent skills are installed

# land_vpath PAYLOADPATH: where a path of the release payload lives in a consumer (a skill goes to .agents/skills/, everything else under $LAND_DIR).
land_vpath() { case "$1" in skills/*) echo ".agents/$1";; *) echo "$LAND_DIR/$1";; esac; }
