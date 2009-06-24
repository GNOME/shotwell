/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

/*
 * FStream is a patch of the GLib FileStream object.  FileStream does not offer fread() and fwrite()
 * wrappers, which is needed for Exif (and possibly other) functions.  Rather than patching GLib,
 * the extended code is here.  Should be easily removed if/when GLib is patched.
 */
[Compact]
[CCode (cname = "FILE", free_function = "fclose", cheader_filename = "stdio.h")]
public class FStream {
	[CCode (cname = "fopen")]
	public static FStream? open (string path, string mode);
	[CCode (cname = "fdopen")]
	public static FStream? fdopen (int fildes, string mode);
	[CCode (cname = "fprintf")]
	[PrintfFormat ()]
	public void printf (string format, ...);
	[CCode (cname = "fputc", instance_pos = -1)]
	public void putc (char c);
	[CCode (cname = "fputs", instance_pos = -1)]
	public void puts (string s);
	[CCode (cname = "fgetc")]
	public int getc ();
	[CCode (cname = "fgets", instance_pos = -1)]
	public weak string gets (char[] s);
	[CCode (cname = "feof")]
	public bool eof ();
	[CCode (cname = "fscanf")]
	public int scanf (string format, ...);
	[CCode (cname = "fflush")]
	public int flush ();
	[CCode (cname = "fseek")]
	public int seek (long offset, GLib.FileSeek whence);
	[CCode (cname = "ftell")]
	public long tell ();
	[CCode (cname = "rewind")]
	public void rewind ();
	[CCode (cname = "fileno")]
	public int fileno ();
	[CCode (cname = "ferror")]
	public int error ();
	[CCode (cname = "clearerr")]
	public void clearerr ();
	[CCode (cname = "fread", instance_pos = -1)]
	public size_t read (void *ptr, size_t size, size_t count);
	[CCode (cname = "fwrite", instance_pos = -1)]
	public size_t write (void *ptr, size_t size, size_t count);
}

