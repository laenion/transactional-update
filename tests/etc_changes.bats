setup() {
	bats_require_minimum_version 1.5.0
	cd "$( dirname "$BATS_TEST_FILENAME" )"

	mockdir_old_etc="$(mktemp --directory /tmp/transactional-update.synctest.olddir.XXXX)" # Simulates changed files after snapshot creation
	mockdir_new_etc="$(mktemp --directory /tmp/transactional-update.synctest.newdir.XXXX)"
	mockdir_syncpoint="$(mktemp --directory /tmp/transactional-update.synctest.syncdir.XXXX)"
}

teardown() {
	rm -rf "${mockdir_old_etc}" "${mockdir_new_etc}" "${mockdir_syncpoint}"
}

createFile() {
	echo "Creating file '${PWD}/$1'..."
	echo "Test" > "$1"
}

@test "Special characters in file names" {
	pushd "${mockdir_old_etc}"
	createFile 'File with spaces.txt'
	createFile 'File
		with
		newlines and tabs.txt'
	createFile 'rsync special characters: * \ ?.txt'
	createFile 'rsync escape sequence in an actual file name: \#012.txt'
	createFile 'Bash special characters: " '"'"' ( ).txt'

	popd

	../dracut/transactional-update-etc-cleaner.sh "${mockdir_old_etc}" "${mockdir_new_etc}" "${mockdir_syncpoint}"
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
