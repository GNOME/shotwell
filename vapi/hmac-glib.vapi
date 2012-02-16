/* Copyright 2010-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */
namespace GLib {
    [CCode (cheader_filename="glib.h", cname="g_compute_hmac_for_string")]
    string compute_hmac_for_string(ChecksumType hash_kind, string key, size_t key_length,
        string data, size_t data_length);
}

