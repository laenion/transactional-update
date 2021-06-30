/*
 SPDX-License-Identifier: LGPL-2.1-or-later */
/* SPDX-FileCopyrightText: 2020 SUSE LLC */

/*
  This is the EXPERIMENTAL C API for tukit. For the moment it is only inteded
  for internal use.
  For documentation please see the corresponding classes in the C++ header
  files.
 */

#ifndef T_U_TUKIT_H
#define T_U_TUKIT_H
#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    None=0, Error, Info, Debug
} loglevel;

const char* tukit_get_errmsg();
void tukit_set_loglevel(loglevel lv);
typedef void* tukit_tx;
tukit_tx tukit_new_tx();
void tukit_free_tx(tukit_tx tx);
int tukit_tx_init(tukit_tx tx, char* base);
int tukit_tx_resume(tukit_tx tx, char* id);
int tukit_tx_execute(tukit_tx tx, char* argv[]);
int tukit_tx_execute_none_chroot(tukit_tx tx, char* argv[]);  
int tukit_tx_finalize(tukit_tx tx);
int tukit_tx_keep(tukit_tx tx);
int tukit_tx_is_initialized(tukit_tx tx);
const char* tukit_tx_get_snapshot(tukit_tx tx);
const char* tukit_tx_get_root(tukit_tx tx);

#ifdef __cplusplus
}
#endif
#endif // T_U_TUKIT_H
