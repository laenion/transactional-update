#!/bin/bash -e
#
# Check for conflicts in etc overlay on first boot after creating new snapshot
#
# Author: Ignaz Forster <iforster@suse.com>
# Copyright (C) 2024 SUSE LLC
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

if [ -e /etc/etc.syncpoint -o $# -eq 3 ]; then
  echo "First boot of snapshot: Merging /etc changes..."

  if [ $# -eq 3 ]; then
    parentdir="$1"
    currentdir="$2"
    syncpoint="$3"
  else
    syncpoint="/etc/etc.syncpoint/"
    parent="$(< "${syncpoint}/transactional-update.comparewith")"
    parentdir="/.snapshots/${parent}/snapshot/etc/"
    currentdir="/etc/"
  fi
  excludesfile="$(mktemp "${syncpoint}/transactional-update.sync.changedinnewsnap.XXXXXX)")"
  # TODO: Mount parent /etc here for migrations from old overlay to new subvolumes
  rsync --archive --inplace --xattrs --acls --delete --progress "${parentdir}" "${syncpoint}" | tail -n +3 > "${excludesfile}"
  # `rsync` and `echo` are using a different format to represent octals ("\#xxx" vs. "\xxx"); convert to `echo` syntax
  sed -i 's/\\#\([0-9]\{3\}\)/\\0\1/g' "${excludesfile}"
  # Escape all escapes because they will also be parsed by the following echo, and write them all into a nul-separated file, so that we don't mix up end of filename and newline because they are unescaped now
  sed 's/\\/\\\\/g' "${excludesfile}" | while read file; do echo -en "$file\0"; done > "${excludesfile}.tmp"
  mv "${excludesfile}.tmp" "${excludesfile}"

exit

  rsync --dry-run /.snapshots/10/snapshot/etc/ /.snapshots/14/snapshot/etc/ --archive | tail -n +3 > /tmp/file
  sed 's/\\#\([0-9]\{3\}\)/\\0\1/g' /tmp/file | sed 's/\\/\\\\/g' | while read file; do echo -en "$file\0"; done > bla
  rsync --dry-run /.snapshots/10/snapshot/etc/ /.snapshots/14/snapshot/etc/ --from0 --archive --progress --exclude-from=bla


# rsync \#xxx (three digits) have to be replaced with their octal value
  sed 's/\\#\([0-9]\{3\}\)/\\0\1/g' /tmp/file | sed 's/\[/\\[/g' | sed 's/?/\?/g' | sed 's/*/\*/g' | sed 's/^\(.\)/[\1]/g' | sed 's/\\/\\\\/g' | tr '\n' '\0' > /tmp/file2
  while read file; do echo -e $file; done < /tmp/file2
  ARRAY=()
  while read file; do ARRAY+=($file); done < /tmp/file2
  for file in "${ARRAY[@]}"; do echo -e Hallo $file; done

  IFS=$'\0' tr '\n' '\0' < /tmp/file | sed 's/\\#\([0-9]\{3\}\)/\\0\1/g' | sed 's/\[/\\[/g' | sed 's/?/\?/g' | sed 's/*/\*/g' | sed 's/^\(.\)/[\1]/g' | sed 's/\\/\\\\/g' > /tmp/file2
 
# Test with newline, Leerzeichen, ', *, Datei die '\#012' im Namen beinhaltet, welches nicht zu einem Newline expandiert werden darf
fi


TU_FLAGFILE="${NEWROOT}/var/lib/overlay/transactional-update.newsnapshot"

# Import common dracut variables
. /dracut-state.sh 2>/dev/null

warn_on_conflicting_files() {
  local dir="${1:-.}"
  local file
  local basedir="${PREV_ETC_OVERLAY}/${dir}"
  local checkdir="${CURRENT_ETC_OVERLAY}/${dir}"

  echo "Checking for conflicts between ${PREV_ETC_OVERLAY}/${dir} and ${CURRENT_ETC_OVERLAY}/${dir}..."

  pushd "${checkdir}" >/dev/null
  for file in .[^.]* ..?* *; do
    # Filter unexpanded globs of "for" loop
    if [ ! -e "${file}" ]; then
      continue
    fi

    # Check whether a file present in a newer layer is also present in the
    # original layer and has a timestamp from after branching the (first)
    # snapshot.
    if [ -e "${basedir}/${file}" -a "${basedir}/${file}" -nt "${NEW_OVERLAYS[-1]}" ]; then
      echo "WARNING: ${dir}/${file} or its contents changed in both old and new snapshot after snapshot creation!"
    fi

    # Recursively process directories
    if [ -d "${file}" ]; then
      warn_on_conflicting_files "${dir}/${file}"
    fi
  done
  popd >/dev/null
}

if [ -e "${TU_FLAGFILE}" ]; then
  CURRENT_SNAPSHOT_ID="`findmnt /${NEWROOT} | sed -n 's#.*\[/@/\.snapshots/\([[:digit:]]\+\)/snapshot\].*#\1#p'`"
  . "${TU_FLAGFILE}"

  CURRENT_ETC_OVERLAY="${NEWROOT}/var/lib/overlay/${CURRENT_SNAPSHOT_ID}/etc"
  PREV_ETC_OVERLAY="${NEWROOT}/var/lib/overlay/${PREV_SNAPSHOT_ID}/etc"

  if [ "${CURRENT_SNAPSHOT_ID}" = "${EXPECTED_SNAPSHOT_ID}" -a -e "${CURRENT_ETC_OVERLAY}" ]; then
    NEW_OVERLAYS=()
    for option in `findmnt --noheadings --output OPTIONS /${NEWROOT}/etc | tr ',' ' '`; do
      case "${option%=*}" in
        upperdir)
          NEW_OVERLAYS[0]="${option#*=}"
          ;;
        lowerdir)
          # If the previous overlay is not part of the stack just skip
          if [[ $option != *"${PREV_ETC_OVERLAY}"* ]]; then
            NEW_OVERLAYS=()
            break
          fi

          i=1
          for lowerdir in `echo ${option#*=} | tr ':' ' '`; do
            if [ ${lowerdir} = ${PREV_ETC_OVERLAY} ]; then
              break
            fi
            NEW_OVERLAYS[$i]="${lowerdir}"
            ((i++))
          done
          ;;
      esac
    done

    rm "${TU_FLAGFILE}"

    for overlay in "${NEW_OVERLAYS[@]}"; do
      CURRENT_ETC_OVERLAY="${overlay}"
      warn_on_conflicting_files
    done
  fi
fi
