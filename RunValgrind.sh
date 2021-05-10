#!/bin/bash

# Usage:
# 0) Install valgrind with JVM-related patches
#    Default valgrind is not going to work due to JVM stack probes.
#    a) Clone https://github.com/SyntevoAlex/valgrind.git
#    b) ./autogen.sh
#    c) ./configure
#    d) make
#    e) sudo make install
# 1) Compose your full java commandline as usual
# 2) Add -Xint to Java commanline. Valgrind is not very happy with JIT.
# 3) Prepend this script's path to the java's commandline
# 4) Run. Note that it usually takes some 2 minutes for Java to start under valgrind.
# 5) Find a copy of valgrind's output in a new file near this script

SCRIPT_DIR=`dirname "$0"`

# --------------
# Configure GLib
# --------------

# Do not use GLib's internal allocators that will not be visible to leak detector
export G_SLICE=always-malloc
# This option is usually recommended for Valgrind
export G_DEBUG=gc-friendly

# ---------------------------------
# Vagrind options suitable for Java
# ---------------------------------

# Detect memory leaks
VALGRIND_ARGS=(--tool=memcheck)

# Level of details for detected leaks:
#   'summary' will only output the number of leaks.
#   'full' is a lot more helpful, also giving stacks.
# VALGRIND_ARGS+=(--leak-check=summary)
VALGRIND_ARGS+=(--leak-check=full)

# Show all leaks, including 'still reachable' ones
VALGRIND_ARGS+=(--show-leak-kinds=all)

# Not sure if this is actually needed
VALGRIND_ARGS+=(--smc-check=all)

# GTK and fontconfig tend to have pretty long stacks.
# Increase the number of callers captured in call stacks to reliably suppress
# false positives and give more information for actual leaks. The downside is
# that found leaks with the same culprit will tend to break into many smaller
# groups.
VALGRIND_ARGS+=(--num-callers=30)

# JVM's stack probe (AbstractAssembler::generate_stack_overflow_check()) causes
# valgrind to be upset with thousands of writes that are seemingly below current
# stack pointer. Unfortunately, valgrind can't see JVM's internals, so there's
# no reliable way to filter these errors out. So we're going to disable any
# errors like 'Invalid write of size 4 ... xxx bytes below stack pointer'. The
# downside is that we won't be detecting actual errors elsewhere. If you want to
# try to detect such problems, disable the option and 'jvm_stackprobe.supp' will
# try to do the magic to filter these errors out, but that's not very reliable and
# slows down valgrind.
#
# Note: in default valgrind, range is limited to 4096. Use valgrind with patches,
# see the header of this script.
VALGRIND_ARGS+=(--ignore-range-below-sp=81920-1)

# Ignore errors like 'Use of uninitialised value of size 8'
VALGRIND_ARGS+=(--undef-value-errors=no)

# ------------------------------------------
# Suppress findings that are not interesting
# ------------------------------------------

# Add all suppression files to avoid the noise caused by 3rd party things
VALGRIND_ARGS+=(--suppressions="$SCRIPT_DIR/Suppressions/3rd_party/glib/glib.supp")
VALGRIND_ARGS+=(--suppressions="$SCRIPT_DIR/Suppressions/3rd_party/gtk/gtk.supp")

for suppressionFile in $SCRIPT_DIR/Suppressions/*.supp
do
	VALGRIND_ARGS+=(--suppressions=$suppressionFile)
done

# Help to make suppressions
# VALGRIND_ARGS+=(--gen-suppressions=yes)

# ------------------
# Debugging with gdb
# ------------------

# Use this commandline command to connect gdb
#   gdb -ex 'target remote | vgdb' java

# Enable debugging with gdb
# VALGRIND_ARGS+=(--vgdb=yes)

# valgrind: attach gdb immediately instead of on first error
# VALGRIND_ARGS+=(--vgdb-error=0)

# --------------------
# Prepare the log file
# --------------------

VALGIND_LOG_FILE="$SCRIPT_DIR/valgrind-$(date +%Y%m%d-%H%M%S).log"
touch "$VALGIND_LOG_FILE"

# Start the annotator to inject some useful information into the log
if [ true ]; then
	(
		ANNOTATED_PID=$$

		while [ true ]; do
			if ! annotation="$(ps -o time= -o rss= $ANNOTATED_PID)"; then
				# Annotated process exited
				exit 0
			fi
			
			annotationTokens=($annotation)
			echo "[Time=${annotationTokens[0]} RES=${annotationTokens[1]}]" >> "$VALGIND_LOG_FILE"
			sleep 10s
		done
	) &
fi

# Redirect all valgrind output to the log file
exec &> >(tee -a "$VALGIND_LOG_FILE")

# ---------------------
# Finally, run valgrind
# ---------------------

# 'exec' is used to keep the PID passed to annotator
exec valgrind "${VALGRIND_ARGS[@]}" -- "$@"

