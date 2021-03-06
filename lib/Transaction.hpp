/*
 SPDX-License-Identifier: LGPL-2.1-or-later */
/* SPDX-FileCopyrightText: 2020 SUSE LLC */

/*
  A Transaction is unique instance, shared between all classes derived from
  the "TransactionalCommand" base class; that way it is made sure that all
  commands operate on the same snapshot. In case the destructor should be
  called before the transaction instance is closed, an eventual snapshot will
  be deleted again.
 */

#ifndef T_U_TRANSACTION_H
#define T_U_TRANSACTION_H

#include <algorithm>
#include <filesystem>
#include <memory>
#include <vector>

namespace TransactionalUpdate {

class Transaction {
public:
    /**
     * @brief Constructor for a new Transaction object
     *
     * The Transaction constructor will determine which snapshotting mechanism to use, but will
     * not change the system itself. It is required to either init() or resume() a session.
     */
    Transaction();

    /**
     * @brief Destructor
     *
     * If the destructor is triggered and the snapshot hasn't been persisted with finalize()
     * or keep(), then the snapshot will be purged again.
     */
    virtual ~Transaction();

    /**
     * @brief Open a new transaction
     * @param base Snapshot ID, "active" or "default"
     *
     * Create a new snapshot, based on the given @base.
     * @base can be "active" to base the snapshot on the currently running system, "default" to
     * the current default snapshot as a base (which may or may not be identical to "active")
     * or any specific existing snapshot id.
     *
     * If @base is not set "active" will be used as the default.
     */
    void init(std::string base);

    /**
     * @brief Resume an existing transaction
     * @param id Snapshot ID
     *
     * Resume a transaction closed with keep().
     */
    void resume(std::string id);

    /**
     * @brief Execute the given application in the new snapshot
     * @param argv
     * @return application's return code
     *
     * Execute any given command in the new snapshot. The application's output will not be
     * modified and printed to the corresponding streams.
     *
     * Note that @param is following the default C style syntax:
     * @example: char *args[] = {(char*)"ls", (char*)"-l", NULL};
                 int status = transaction.execute(args);
     */
    int execute(char* argv[]);

    /**
     * @brief Close a transaction and set it as the new default snapshot
     *
     * Note that it is necessary to call this method if the snapshot is supposed to be kept.
     * Failing to do so will remove the snapshot as soon as the Transaction's destructor is
     * called.
     */
    void finalize();

    /**
     * @brief Don't discard transaction on destructor call
     *
     * It is possible to keep a transaction open even though the Transaction object has been
     * destructed. Such a transaction can be resumed later using resume(), but it won't be set
     * as the new default snapshot as long as it is still open.
     *
     * Note that such pending transactions will still be marked for cleanup by
     * transactional-update to avoid collecting unfinished / never closed snapshots
     */
    void keep();

    /**
     * @brief Check whether a snapshot has been initialized already
     * @return
     *
     * True if init() or resume() have been called successfully.
     */
    bool isInitialized();

    /**
     * @brief Return the snapshot ID
     * @return snapshot ID
     *
     * May be used for resume() or general information.
     */
    std::string getSnapshot();

    /**
     * @brief Return the root path of the snapshot
     * @return root path
     *
     * To actually operate on the path the Transaction should still be open: On a read-only
     * system the new snapshot's path will be set read-only as soon as finalize() is called.
     * Also auxiliary mounts such as /etc will only be bind mounted into the new snapshot's
     * root path as long as Transaction's destructor hasn't been called.
     */
    std::filesystem::path getRoot();
private:
    class impl;
    std::unique_ptr<impl> pImpl;
};

} // namespace TransactionalUpdate

#endif // T_U_TRANSACTION_H
