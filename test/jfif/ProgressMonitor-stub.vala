// SPDX-FileCopyrightText: Software Freedom Conservancy Inc.
// SPDX-License-Identifier: LGPL-2.1-or-later
// Needed to include util/file.vala without core/util.vala as well
public delegate bool ProgressMonitor(uint64 current, uint64 total, bool do_event_loop = true);
