/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */


public class PrintJob : Gtk.PrintOperation {
    private PrintSettings settings;
    private Gee.ArrayList<Photo> photos = new Gee.ArrayList<Photo>();
    
    public PrintJob(Gee.Collection<Photo> to_print) {
        this.settings = PrintManager.get_instance().get_global_settings();
        photos.add_all(to_print);
        
        set_embed_page_setup (true);
        double photo_aspect_ratio =  photos[0].get_dimensions().get_aspect_ratio();
        if (photo_aspect_ratio < 1.0)
            photo_aspect_ratio = 1.0 / photo_aspect_ratio;
    }

    public Gee.List<Photo> get_photos() {
        return photos;
    }

    public Photo get_source_photo() {
        return photos[0];
    }

    public double get_source_aspect_ratio() {
        double aspect_ratio = photos[0].get_dimensions().get_aspect_ratio();
        return (aspect_ratio < 1.0) ? (1.0 / aspect_ratio) : aspect_ratio;
    }

    public PrintSettings get_local_settings() {
        return settings;
    }

    public void set_local_settings(PrintSettings settings) {
        this.settings = settings;
    }
}
