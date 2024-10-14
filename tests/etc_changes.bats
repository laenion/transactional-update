setup() {
	cd "$( dirname "$BATS_TEST_FILENAME" )"

	mockdir_old_etc="$(mktemp --directory /tmp/transactional-update.synctest.olddir.XXXX)" # Simulates changed files after snapshot creation
	mockdir_new_etc="$(mktemp --directory /tmp/transactional-update.synctest.newdir.XXXX)"
	mockdir_syncpoint="$(mktemp --directory /tmp/transactional-update.synctest.syncdir.XXXX)"
}

teardown() {
	rm -rf "${mockdir_old_etc}" "${mockdir_new_etc}" "${mockdir_syncpoint}"
}

SPECIAL_FILENAMES=('NULL' '- looks like an exclude' '# looks like a comment' '; looks like a comment' '[ is a bracket as a first character' '\ is a backslash as the first character' 'File
                with spaces,
                newlines and tabs.txt' 'rsync special characters: * \ ?.txt' 'rsync escape sequence in an actual file name: \#012.txt' 'Bash special characters: " '"'"' ( ).txt')

createFile() {
	echo "# Creating file '${PWD}/$1'..."
	echo "Test" > "$1"
}

createFilesWithSpecialFilenames() {
	for file in "${SPECIAL_FILENAMES[@]}"; do
		createFile "${file}"
	done
}

checkFilesWithSpecialFilenames() {
	local ret=0
	for file in "${SPECIAL_FILENAMES[@]}"; do
		echo -n "# Checking for existence of '${PWD}/${file}' - "
		if [ -e "${mockdir_new_etc}/${file}" ]; then
			echo "Found"
		else
			echo "Not found"
			ret=1
		fi
	done
	return ${ret}
}

debug() {
	echo
	echo "# Contents of exclude file:"
	cat "${mockdir_syncpoint}/transactional-update.sync.changedinnewsnap."*
	echo
	#echo "# Directory listing:"
	#find /tmp/transactional-update.synctest*
	#echo
}

@test "Special characters in file names (must not be deleted)" {
	pushd "${mockdir_new_etc}"
	createFilesWithSpecialFilenames
	popd

	../dracut/transactional-update-etc-cleaner.sh "${mockdir_old_etc}" "${mockdir_new_etc}" "${mockdir_syncpoint}"

	debug

	pushd "${mockdir_new_etc}"
	checkFilesWithSpecialFilenames
	popd
}

@test "Special characters in file names (to be synced)" {
	pushd "${mockdir_old_etc}"
	createFilesWithSpecialFilenames
	popd

	../dracut/transactional-update-etc-cleaner.sh "${mockdir_old_etc}" "${mockdir_new_etc}" "${mockdir_syncpoint}"

	debug

	pushd "${mockdir_new_etc}"
	checkFilesWithSpecialFilenames
	popd
}

#cd /etc
#
## Step 1: Prepare environment
#if [ $1 = 0 ]; then
#	rm -rf existing_* insnap_* aftersnap_*
#	echo Test > existing_nochanges.txt
#	echo Test > existing_change_content.txt
#	echo Test > existing_attribute_changes.txt
#	echo Test > existing_xattr_changes.txt
#	mkdir -p existing_directory/existing_subdir
#	cd existing_directory
#	echo Test > existing_nochanges.txt
#	echo Test > existing_change_content.txt
#	echo Test > existing_attribute_changes.txt
#	echo Test > existing_xattr_changes.txt
#	cd existing_subdir
#	echo Test > existing_nochanges.txt
#	echo Test > existing_change_content.txt
#	echo Test > existing_attribute_changes.txt
#	echo Test > existing_xattr_changes.txt
#	cd ../..
#	mkdir -p existing_dir_for_move/dir1
#	touch existing_dir_for_move/file1.txt
#
#	sync
#	transactional-update grub.cfg
#fi
#
#if [ $1 = 1 ]; then
#	echo Hello > insnap_new_file.txt
#	echo "# `date`" >> existing_change_content.txt
#	chmod u+x existing_attribute_changes.txt
#	setfattr -n user.test -v "`date`" existing_xattr_changes.txt
#
#	# Create files for modification after snapshot creation
#	touch insnap_change_permissions.txt
#	touch insnap_change_xattrs.txt
#	mkdir -p insnap_new_dir_for_changes/will_be_merged
#	mkdir -p insnap_new_dir_for_changes/will_be_empty
#	mkdir -p insnap_new_dir_for_changes/was_empty_dir
#	mkdir -p insnap_new_dir_for_changes/change_dir_permissions
#	mkdir -p insnap_new_dir_for_changes/to_be_removed
#	mkdir -p insnap_new_dir_for_changes/change_xattr
#	mkdir -p insnap_new_dir_for_changes/nochange
#	touch insnap_new_dir_for_changes/file1.txt
#	touch insnap_new_dir_for_changes/will_be_merged/file1.txt
#	touch insnap_new_dir_for_changes/will_be_empty/file1.txt
#	touch insnap_new_dir_for_changes/change_dir_permissions/file1.txt
#	touch insnap_new_dir_for_changes/to_be_removed/file1.txt
#	touch insnap_new_dir_for_changes/change_xattr/file1.txt
#	touch insnap_new_dir_for_changes/nochange/file1.txt
#	mkdir -p insnap_new_dir_without_changes/somedir
#	touch insnap_new_dir_without_changes/somefile.txt
#	touch insnap_new_dir_without_changes/somedir/somefile.txt
#	mkdir -p insnap_dir_for_move/dir1
#	touch insnap_dir_for_move/file1.txt
#
#	# Create snapshot
#	sync
#	transactional-update grub.cfg
#	sync
#
#	touch aftersnap_new_file.txt
#	touch insnap_new_dir_for_changes/will_be_merged/file2.txt
#	rm insnap_new_dir_for_changes/will_be_empty/file1.txt
#	touch insnap_new_dir_for_changes/was_empty_dir/file2.txt
#	chmod g+w insnap_new_dir_for_changes/change_dir_permissions
#	chmod g+w insnap_change_permissions.txt
#	rm -r insnap_new_dir_for_changes/to_be_removed
#	setfattr -n user.test -v "`date`" insnap_new_dir_for_changes/change_xattr
#	setfattr -n user.test -v "`date`" insnap_change_xattrs.txt
#	mkdir -p aftersnap_new_dir/dir1
#	touch aftersnap_new_dir/file1.txt
#	mv existing_dir_for_move aftersnap_new_existing_location
#	mv insnap_dir_for_move aftersnap_new_insnap_location
#fi
