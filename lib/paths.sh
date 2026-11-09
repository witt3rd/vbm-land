# lib/paths.sh: every path the tool uses inside a consumer repository, defined ONCE. Sourced, never run. Paths are relative to the consumer's root.
LAND_HOME=.land                          # the ONE folder that holds everything the tool owns in a consumer (the skills are the exception: an agent convention)
LAND_DIR=$LAND_HOME/tool                 # the vendored tool folder: replaced whole on every install, never edited
LAND_PIN=$LAND_HOME/PIN                  # version, commit and checksum of the vendored tool (OUTSIDE tool/, so replacing tool/ never removes it)
LAND_MANIFEST_FILE=$LAND_DIR/MANIFEST.sha256   # the per-file checksum list of the vendored tool
LAND_CONF_FILE=$LAND_HOME/land.conf      # the repository's own settings
LAND_HOOKS_DEFAULT=$LAND_HOME/land.d     # the repository's own hooks
LAND_SIGNERS_FILE=$LAND_HOME/land.signers   # who may sign releases
LAND_ENTRY=$LAND_HOME/land-direct        # the entry script an agent runs (it execs ./tool/bin/land-direct beside itself)
LAND_SKILLS_DIR=.agents/skills           # where the tool's agent skills are installed

# land_vpath PAYLOADPATH: where a path of the release payload lives in a consumer (a skill goes to .agents/skills/, everything else under $LAND_DIR).
land_vpath() { case "$1" in skills/*) echo ".agents/$1";; *) echo "$LAND_DIR/$1";; esac; }
