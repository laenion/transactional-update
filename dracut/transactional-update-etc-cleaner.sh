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

if [ "$1" == "--dry-run" -o "$1" == "-n" ]; then
  DRYRUN=1
  shift
fi

if [ -e /etc/etc.syncpoint -o $# -eq 3 ]; then
  echo "First boot of snapshot: Merging /etc changes..."

  if [ $# -eq 3 ]; then
    # Allow overwriting default locations for testing
    parentdir="$1/"
    currentdir="$2/"
    syncpoint="$3/"
  else
    syncpoint="/etc/etc.syncpoint/"
    parent="$(< "${syncpoint}/transactional-update.comparewith")"
    parentdir="/.snapshots/${parent}/snapshot/etc/"
    currentdir="/etc/"
  fi

  declare -A REFERENCEFILES
  declare -A PARENTFILES
  declare -A CURRENTFILES
  declare -A DIFFTOCURRENT

  shopt -s globstar dotglob nullglob

  cd "${syncpoint}"
  for f in **; do
    REFERENCEFILES["${f}"]=.
  done
  cd "${parentdir}"
  for f in **; do
    PARENTFILES["${f}"]=.
  done
  cd "${currentdir}"
  for f in **; do
    CURRENTFILES["${f}"]=.
  done

    # Check which files have been changed in new snapshot
  for file in "${!REFERENCEFILES[@]}"; do
    if [ -z "${CURRENTFILES[${file}]}" ]; then
      echo "File '$file' got deleted in new snapshot."
      DIFFTOCURRENT[${file}]=recursiveskip
    elif [ -d "${currentdir}/${file}" -a "$(stat --printf="%a %B %F %g %u %Y" "${syncpoint}/${file}")" != "$(stat --printf="%a %B %F %g %u %Y" "${currentdir}/${file}")" ]; then
      echo "Directory '$file' was changed in new snapshot."
      DIFFTOCURRENT[${file}]=skip
    elif [ ! -d "${currentdir}/${file}" -a "$(stat --printf="%a %B %F %g %s %u %Y" "${syncpoint}/${file}")" != "$(stat --printf="%a %B %F %g %s %u %Y" "${currentdir}/${file}")" ]; then
      echo "File '$file' was changed in new snapshot."
      DIFFTOCURRENT[${file}]=skip
    elif [ "$(getfattr --no-dereference --dump --match='' "${syncpoint}/${file}" 2>&1 | tail --lines=+3)" != "$(getfattr --no-dereference --dump --match='' "${currentdir}/${file}" 2>&1 | tail --lines=+3)" ]; then
      echo "Extended file attributes of '$file' were changed in new snapshot."
      DIFFTOCURRENT[${file}]=skip
    fi
  done
  for file in "${!CURRENTFILES[@]}"; do
    if [ -z "${REFERENCEFILES[${file}]}" ]; then
      echo "File or directory '$file' was added in new snapshot."
      DIFFTOCURRENT[${file}]=skip
    fi
  done

  # Check which files have been changed in old snapshot
  for file in "${!REFERENCEFILES[@]}"; do
    if [ -z "${PARENTFILES[${file}]}" ]; then
      echo "File '$file' got deleted in old snapshot."
      if [ -z "${DIFFTOCURRENT[${file}]}" ]; then
        DIFFTOCURRENT[${file}]=delete
        if [ -d "${currentdir}/${file}" ]; then
          for index in "${!DIFFTOCURRENT[@]}"; do
            # If dir and some file was changed or added in new snapshot, then don't delete
            if [[ ${index} == "${file}/"* ]]; then
              DIFFTOCURRENT[${file}]=skip
            fi
          done
        fi
      fi
    elif [ -d "${parentdir}/${file}" -a "$(stat --printf="%a %B %F %g %u %Y" "${syncpoint}/${file}")" != "$(stat --printf="%a %B %F %g %u %Y" "${parentdir}/${file}")" ]; then
      echo "Directory '$file' was changed in old snapshot."
      if [ -z "${DIFFTOCURRENT[${file}]}" ]; then
        DIFFTOCURRENT[${file}]=copy # cp -a for file; touch, chmod, chown with reference file for directory
      fi
    elif [ ! -d "${parentdir}/${file}" -a "$(stat --printf="%a %B %F %g %s %u %Y" "${syncpoint}/${file}")" != "$(stat --printf="%a %B %F %g %s %u %Y" "${parentdir}/${file}")" ]; then
      echo "File '$file' was changed in old snapshot."
      if [ -z "${DIFFTOCURRENT[${file}]}" ]; then
        DIFFTOCURRENT[${file}]=copy # cp -a for file; touch, chmod, chown with reference file for directory
      fi
    elif [ "$(getfattr --no-dereference --dump --match='' "${syncpoint}/${file}" 2>&1 | tail --lines=+3)" != "$(getfattr --no-dereference --dump --match='' "${parentdir}/${file}" 2>&1 | tail --lines=+3)" ]; then
      echo "Extended file attributes of '$file' were changed in old snapshot."
      if [ -z "${DIFFTOCURRENT[${file}]}" ]; then
        DIFFTOCURRENT[${file}]=copy # getfattr --dump & setfattr --restore
      fi
    fi
  done
  for file in "${!PARENTFILES[@]}"; do
    if [ -z "${REFERENCEFILES[${file}]}" ]; then
      echo "File or directory '$file' was added in old snapshot."
      if [ -z "${DIFFTOCURRENT[${file}]}" ]; then
        DIFFTOCURRENT[${file}]=copy
      fi
    fi
  done

  # Sort files to prevent processing a file before the directory was created
  readarray -d '' DIFFTOCURRENT_SORTED < <(printf '%s\0' "${!DIFFTOCURRENT[@]}" | sort -z)

  for file in "${DIFFTOCURRENT_SORTED[@]}"; do
    if [ "${DIFFTOCURRENT[${file}]}" = "recursiveskip" ]; then
      for index in "${!DIFFTOCURRENT[@]}"; do
        if [[ ${index} == "${file}/"* ]]; then
          DIFFTOCURRENT[${index}]=skip
        fi
      done
    elif [ "${DIFFTOCURRENT[${file}]}" = "delete" ]; then
      rm -rf "${currentdir}/${file}"
    elif [ "${DIFFTOCURRENT[${file}]}" = "copy" ]; then
      if [ -f "${parentdir}/${file}" -a -d "${currentdir}/${file}" ] || [ -d "${parentdir}/${file}" -a -f "${currentdir}/${file}" ]; then
        echo "File ${file} changed type between file and directory."
        if [ -z "${DRYRUN}" ]; then
          rm -r "${currentdir}/${file}"
        fi
      fi
      if [ -d "${parentdir}/${file}" ]; then
        if [ -z "${DRYRUN}" ]; then
          mkdir --parents "${currentdir}/${file}"
          touch --no-dereference --reference="${parentdir}/${file}" "${currentdir}/${file}"
          chmod --no-dereference --reference="${parentdir}/${file}" "${currentdir}/${file}"
          chown --no-dereference --reference="${parentdir}/${file}" "${currentdir}/${file}"

          pushd "${parentdir}" >/dev/null
          extattrs="$(getfattr --no-dereference --dump -- "${file}")"
          pushd "${currentdir}" >/dev/null
          echo "${extattrs}" | setfattr --no-dereference --restore=-
          popd >/dev/null
          popd >/dev/null
        fi
      else
        if [ -z "${DRYRUN}" ]; then
          cp --no-dereference --archive "${parentdir}/${file}" "${currentdir}/${file}"
        fi
      fi
    fi
  done

# Border cases, which are defined as follows for now (mostly matching overlayfs' behavior):
# * If a directory was newly created both in old and new after snapshot creation, then the contents of both are merged
# * If a directory was deleted in new, but has changes or new files in old, then it stays deleted
# * If a directory was deleted in old, but has changes or new files in new, then take contents of new

exit

  # Check for files changed in new snapshot during update and create excludes list
  excludesfile="$(mktemp "${syncpoint}/transactional-update.sync.changedinnewsnap.XXXXXX)")"
  # TODO: Mount parent /etc here for migrations from old overlay to new subvolumes
  rsync --archive --inplace --xattrs --acls --out-format='%n' --dry-run "${currentdir}" "${syncpoint}" > "${excludesfile}"
  # `rsync` and `echo` are using a different format to represent octals ("\#xxx" vs. "\xxx"); convert to `echo` syntax
  # First escape already escaped characters, then convert the octals, then escape other rsync special characters in filenames
  sed -i 's/\\/\\\\\\\\/g;s/\\\\#\([0-9]\{3\}\)/\\0\1/g;s/\[/\\[/g;s/?/\\?/g;s/*/\\*/g;s/#/\\#/g' "${excludesfile}"
  # Escape all escapes because they will also be parsed by the following echo, and write them all into a nul-separated file, so that we don't mix up end of filename and newline because they are unescaped now; prepend a slash for absolute paths
  sed 's/\\/\\\\/g' "${excludesfile}" | while read file; do echo -en "- $file\0"; done > "${excludesfile}.tmp"
  # Replace the first character of each file with a character class to force rsync's parser to always interpret a backslash in a file name as an escape character
  sed 's/^\(- \)\(.\)/\1[\2]/g;s/\(\x00- \)\(.\)/\1[\2]/g' "${excludesfile}.tmp" > "${excludesfile}"
  # If the first character of a filename was an escaped character, then escape it again correctly by moving the bracket one charater further
  sed -i 's/^\(- \[\\\)\]\(.\)/\1\2]/g;s/\(\x00- \[\\\)\]\(.\)/\1\2]/g' "${excludesfile}"

  # Sync files changed in old snapshot before reboot, but don't overwrite the files from above
  rsync --archive --inplace --xattrs --acls --delete --from0 --exclude-from "${excludesfile}" --itemize-changes "${parentdir}" "${currentdir}"
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
