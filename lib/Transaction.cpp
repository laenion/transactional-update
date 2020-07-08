/*
  The Transaction class is the central API class for the lifecycle of a
  transaction: It will open and close transactions and execute commands in the
  correct context.

  Copyright (c) 2016 - 2020 SUSE LLC

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "Transaction.h"
#include "Configuration.h"
#include "Log.h"
#include "Overlay.h"
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <sys/wait.h>
#include <unistd.h>
using namespace std;

Transaction::Transaction() {
    tulog.debug("Constructor Transaction");
}

Transaction::Transaction(string uuid) {
    snapshot = SnapshotFactory::get();
    snapshot->open(uuid);
    mount();
}

Transaction::~Transaction() {
    tulog.debug("Destructor Transaction");

    supplements.cleanup();

    dirsToMount.clear();
    try {
        filesystem::remove_all(filesystem::path{bindDir});
        if (isInitialized())
            snapshot->abort();
    }  catch (const exception &e) {
        tulog.error("ERROR: ", e.what());
    }
}

bool Transaction::isInitialized() {
    return snapshot ? true : false;
}

string Transaction::getSnapshot()
{
    return snapshot->getUid();
}

void Transaction::mount(string base) {
    dirsToMount.push_back(make_unique<PropagatedBindMount>("/dev"));
    dirsToMount.push_back(make_unique<BindMount>("/var/log"));

    Mount mntVar{"/var"};
    if (mntVar.isMount()) {
        dirsToMount.push_back(make_unique<BindMount>("/var/cache"));
        dirsToMount.push_back(make_unique<BindMount>("/var/lib/alternatives"));
        dirsToMount.push_back(make_unique<BindMount>("/var/lib/ca-certificates", MS_RDONLY));
    }
    unique_ptr<Mount> mntEtc{new Mount{"/etc"}};
    if (mntEtc->isMount() && mntEtc->getFS() == "overlay") {
        Overlay overlay = Overlay{snapshot->getUid()};
        overlay.create(base);

        overlay.setMountOptions(mntEtc);
        mntEtc->persist(snapshot->getRoot() / "etc" / "fstab");
        overlay.setMountOptionsForMount(mntEtc);

        overlay.sync(snapshot->getRoot());

        dirsToMount.push_back(std::move(mntEtc));

        // Make sure both the snapshot and the overlay contain all relevant fstab data, i.e.
        // user modifications from the overlay are present in the root fs and the /etc
        // overlay is visible in the overlay
        filesystem::copy(filesystem::path{snapshot->getRoot() / "etc" / "fstab"}, overlay.upperdir, filesystem::copy_options::overwrite_existing);
    }

    // Mount platform specific GRUB directories for GRUB updates
    for (auto& path: filesystem::directory_iterator("/boot/grub2")) {
        if (filesystem::is_directory(path)) {
            if (BindMount{path.path()}.isMount())
                dirsToMount.push_back(make_unique<BindMount>(path.path()));
        }
    }
    if (BindMount{"/boot/efi"}.isMount())
        dirsToMount.push_back(make_unique<BindMount>("/boot/efi"));

    dirsToMount.push_back(make_unique<PropagatedBindMount>("/proc"));
    dirsToMount.push_back(make_unique<PropagatedBindMount>("/sys"));

    if (BindMount{"/root"}.isMount())
        dirsToMount.push_back(make_unique<BindMount>("/root"));

    if (BindMount{"/boot/writable"}.isMount())
        dirsToMount.push_back(make_unique<BindMount>("/boot/writable"));

    dirsToMount.push_back(make_unique<BindMount>("/.snapshots"));

    for (auto it = dirsToMount.begin(); it != dirsToMount.end(); ++it) {
        it->get()->mount(snapshot->getRoot());
    }

    // When all mounts are set up, then bind mount everything into a temporary
    // directory - GRUB needs to have an actual mount point for the root
    // partition
    char bindTemplate[] = "/tmp/transactional-update-XXXXXX";
    bindDir = mkdtemp(bindTemplate);
    unique_ptr<BindMount> mntBind{new BindMount{bindDir, MS_REC}};
    mntBind->setSource(snapshot->getRoot());
    mntBind->mount();
    dirsToMount.push_back(std::move(mntBind));
}

void Transaction::addSupplements() {
    supplements = Supplements(snapshot->getRoot());

    Mount mntVar{"/var"};
    if (mntVar.isMount()) {
        supplements.addDir(filesystem::path{"/var/tmp"});
        supplements.addFile(filesystem::path{"/var/lib/zypp/RequestedLocales"}); // locale specific packages with zypper
        supplements.addLink(filesystem::path{"/run"}, filesystem::path{"/var/run"});
    }
    supplements.addLink(filesystem::path{"/usr/lib/sysimage/rpm"}, filesystem::path{"/var/lib/rpm"});
    supplements.addFile(filesystem::path{"/run/netconfig"});
    supplements.addDir(filesystem::path{"/var/cache/zypp"});
}

void Transaction::init(string base) {
    snapshot = SnapshotFactory::get();
    if (base == "active")
        base = snapshot->getCurrent();
    else if (base == "default")
        base =snapshot->getDefault();
    snapshot->create(base);

    mount(base);
    addSupplements();
}

int Transaction::execute(const char* argv[]) {
    std::string opts = "Executing `";
    int i = 0;
    while (argv[i]) {
        if (i > 0)
            opts.append(" ");
        opts.append(argv[i]);
        i++;
    }
    opts.append("`:");
    tulog.info(opts);

    int status = 1;
    pid_t pid = fork();
    if (pid < 0) {
        throw runtime_error{"fork() failed: " + string(strerror(errno))};
    } else if (pid == 0) {
        if (chroot(bindDir.c_str()) < 0) {
            throw runtime_error{"Chrooting to " + bindDir + " failed: " + string(strerror(errno))};
        }
        cout << "◸" << flush;
        if (execvp(argv[0], (char* const*)argv) < 0) {
            throw runtime_error{"Calling " + string(argv[0]) + " failed: " + string(strerror(errno))};
        }
    } else {
        int ret;
        ret = waitpid(pid, &status, 0);
        cout << "◿" << endl;
        if (ret < 0) {
            throw runtime_error{"waitpid() failed: " + string(strerror(errno))};
        } else {
            tulog.info("Application returned with exit status ", WEXITSTATUS(status), ".");
        }
    }
    return WEXITSTATUS(status);
}

void Transaction::finalize() {
    snapshot->close();

    std::unique_ptr<Snapshot> defaultSnap = SnapshotFactory::get();
    defaultSnap->open(snapshot->getDefault());
    if (defaultSnap->isReadOnly())
        snapshot->setReadOnly(true);

    snapshot.reset();
}

void Transaction::keep() {
    snapshot.reset();
}
