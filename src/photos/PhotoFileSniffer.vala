/* Copyright 2010-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public class DetectedPhotoInformation {
    public PhotoFileFormat file_format = PhotoFileFormat.UNKNOWN;
    public PhotoMetadata? metadata = null;
    public string? md5 = null;
    public string? exif_md5 = null;
    public string? thumbnail_md5 = null;
    public string? format_name = null;
    public Dimensions image_dim = Dimensions();
    public Gdk.Colorspace colorspace = Gdk.Colorspace.RGB;
    public int channels = 0;
    public int bits_per_channel = 0;
}

//
// A PhotoFileSniffer is expected to examine the supplied file as efficiently as humanly possible
// to detect (a) if it is of a file format supported by the particular sniffer, and (b) fill out
// a DetectedPhotoInformation record and return it to the caller.
//
// The PhotoFileSniffer is not expected to cache information.  It should return a fresh
// DetectedPhotoInformation record each time.
//
// PhotoFileSniffer must be thread-safe.  Like PhotoFileAdapters, it is not expected to guarantee
// atomicity with respect to the filesystem.
//

public abstract class PhotoFileSniffer {
    public enum Options {
        GET_ALL =       0x00000000,
        NO_MD5 =        0x00000001
    }
    
    protected File file;
    protected Options options;
    protected bool calc_md5;
    
    public PhotoFileSniffer(File file, Options options) {
        this.file = file;
        this.options = options;
        
        calc_md5 = (options & Options.NO_MD5) == 0;
    }
    
    public abstract DetectedPhotoInformation? sniff() throws Error;
}

//
// PhotoFileInterrogator
//
// A PhotoFileInterrogator is merely an aggregator of PhotoFileSniffers.  It will create sniffers
// for each supported PhotoFileFormat and see if they recognize the file.
//
// The PhotoFileInterrogator is not thread-safe.
//

public class PhotoFileInterrogator {
    private File file;
    private PhotoFileSniffer.Options options;
    private DetectedPhotoInformation? detected = null;
    
    public PhotoFileInterrogator(File file,
        PhotoFileSniffer.Options options = PhotoFileSniffer.Options.GET_ALL) {
        this.file = file;
        this.options = options;
    }
    
    // This should only be called after interrogate().  Will return null every time, otherwise.
    // If called after interrogate and returns null, that indicates the file is not an image file.
    public DetectedPhotoInformation? get_detected_photo_information() {
        return detected;
    }
    
    public void interrogate() throws Error {
        foreach (PhotoFileFormat file_format in PhotoFileFormat.get_supported()) {
            PhotoFileSniffer sniffer = file_format.create_sniffer(file, options);
            detected = sniffer.sniff();
            if (detected != null) {
                assert(detected.file_format == file_format);
                
                break;
            }
        }
    }
}

