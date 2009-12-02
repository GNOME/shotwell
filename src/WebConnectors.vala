/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

#if !NO_PUBLISHING

public errordomain PublishingError {
    COMMUNICATION
}

public abstract class PublishingDialogPane : Gtk.VBox {
    public virtual void run_interaction() throws PublishingError {
        show_all();
    }
}

public class ProgressPane : PublishingDialogPane {
    private Gtk.ProgressBar progress_bar;
    private Gtk.Label secondary_text;

    public ProgressPane() {
        progress_bar = new Gtk.ProgressBar();
        secondary_text = new Gtk.Label("");
        
        Gtk.HBox progress_bar_wrapper = new Gtk.HBox(false, 0);
        Gtk.SeparatorToolItem left_padding = new Gtk.SeparatorToolItem();
        left_padding.set_size_request(10, -1);
        left_padding.set_draw(false);
        Gtk.SeparatorToolItem right_padding = new Gtk.SeparatorToolItem();
        right_padding.set_size_request(10, -1);
        right_padding.set_draw(false);
        progress_bar_wrapper.add(left_padding);
        progress_bar_wrapper.add(progress_bar);
        progress_bar_wrapper.add(right_padding);

        Gtk.SeparatorToolItem top_padding = new Gtk.SeparatorToolItem();
        top_padding.set_size_request(-1, 100);
        top_padding.set_draw(false);
        Gtk.SeparatorToolItem bottom_padding = new Gtk.SeparatorToolItem();
        bottom_padding.set_size_request(-1, 100);
        bottom_padding.set_draw(false);
        
        add(top_padding);
        add(progress_bar_wrapper);
        add(secondary_text);
        add(bottom_padding);
    }

    public void set_status_text(string text) {
        progress_bar.set_text(text);
    }

    public void set_progress(double progress) {
        progress_bar.set_fraction(progress);
    }
}

class ErrorPane : PublishingDialogPane {
    public ErrorPane() {
        Gtk.Label error_label = new Gtk.Label(_("Publishing can't continue because a communication error occurred.\nMake sure your Internet connection is working."));
        add(error_label);
    }
}

class RestartMessagePane : PublishingDialogPane {
    public RestartMessagePane() {
        Gtk.Label error_label = new Gtk.Label(_("You have already logged in and out of Facebook during this Shotwell session.\nTo continue publishing to Facebook, quit and restart Shotwell, then try publishing again."));
        add(error_label);
    }
}

class SuccessPane : PublishingDialogPane {
    public SuccessPane() {
        Gtk.Label error_label = new Gtk.Label(_("The selected photos were successfully published."));
        add(error_label);
    }
}

public class PublishingDialog : Gtk.Dialog {
    private const string TEMP_FILE_PREFIX = "publishing-";
    
    private static PublishingDialog active_instance = null;
    
    private Gtk.ComboBox service_selector_box;
    private Gtk.Label service_selector_box_label;
    private Gtk.VBox central_area_layouter;
    private Gtk.Button close_cancel_button;
    private FacebookConnector.Session facebook_session;
    private Gee.Iterable<DataView> target_collection;
    private int num_items;
    private bool user_cancelled = false;
    private Gtk.Widget active_pane;
    FacebookConnector.LoginShell facebook_login_shell;

    public PublishingDialog(Gee.Iterable<DataView> to_publish, int publish_num_items) {
        active_instance = this;

        set_title(_("Publish Photos"));
        set_size_request(600, 480);
        resizable = false;
        delete_event += on_window_close;

        target_collection = to_publish;
        num_items = publish_num_items;

        service_selector_box = new Gtk.ComboBox.text();
        service_selector_box.append_text(_("Facebook"));
        service_selector_box.set_active(0);
        service_selector_box_label = new Gtk.Label(_("Publish photos to:"));
        service_selector_box_label.set_alignment(0.0f, 0.5f);

        Gtk.HBox service_selector_layouter = new Gtk.HBox(false, 8);
        service_selector_layouter.set_border_width(12);
        service_selector_layouter.add(service_selector_box_label);
        service_selector_layouter.add(service_selector_box);
        
        central_area_layouter = new Gtk.VBox(false, 8);
        central_area_layouter.set_size_request(500, 368);

        Gtk.HSeparator service_central_separator = new Gtk.HSeparator();

        vbox.add(service_selector_layouter);
        vbox.add(service_central_separator);
        vbox.add(central_area_layouter);
        service_selector_layouter.show_all();
        central_area_layouter.show_all();
        service_central_separator.show_all();
        
        close_cancel_button = new Gtk.Button();
        close_cancel_button.set_label(_("Cancel"));
        close_cancel_button.clicked += on_close_cancel_clicked;
        action_area.add(close_cancel_button);
        close_cancel_button.show_all();
        
        if (FacebookConnector.is_persistent_session_valid()) {
            Config config = Config.get_instance();
            facebook_session = new FacebookConnector.Session(config.get_facebook_session_key(),
                config.get_facebook_session_secret(), config.get_facebook_uid(),
                FacebookConnector.API_KEY, config.get_facebook_user_name());

            FacebookConnector.UploadPane facebook_upload_pane =
                new FacebookConnector.UploadPane(facebook_session);
            facebook_upload_pane.logout += on_facebook_logout;
            facebook_upload_pane.publish += on_facebook_publish;
            central_area_layouter.add(facebook_upload_pane);
            central_area_layouter.show_all();        
            active_pane = facebook_upload_pane;
            try {
                facebook_upload_pane.run_interaction();
            } catch (PublishingError e) {
                on_error();
            }
        } else {
            if (FacebookConnector.LoginShell.get_is_cache_dirty()) {
                PublishingDialogPane restart_pane = new RestartMessagePane();
                central_area_layouter.add(restart_pane);
                central_area_layouter.show_all();
                
                active_pane = restart_pane;

                close_cancel_button.set_label(_("Close"));
            } else {
                FacebookConnector.NotLoggedInPane not_logged_in_pane =
                    new FacebookConnector.NotLoggedInPane();
                not_logged_in_pane.login_requested += on_login_requested;
                central_area_layouter.add(not_logged_in_pane);
                central_area_layouter.show_all();
                
                active_pane = not_logged_in_pane;
            }
        }
    }
    
    private void on_login_requested() {
        facebook_login_shell = new FacebookConnector.LoginShell();
        facebook_login_shell.login_failure += on_facebook_login_failed;
        facebook_login_shell.login_success += on_facebook_login_success;
        facebook_login_shell.login_error += on_facebook_login_error;
        central_area_layouter.remove(active_pane);
        central_area_layouter.add(facebook_login_shell);
        central_area_layouter.show_all();

        active_pane = facebook_login_shell;
        
        facebook_login_shell.load_login_page();
    }
   
    private void on_close_cancel_clicked() {
        user_cancelled = true;
        hide();
        destroy();
    }
    
    private bool on_window_close(Gdk.Event evt) {
        hide();
        destroy();

        return true;
    }
    
    public void on_error() {
        central_area_layouter.remove(active_pane);

        ErrorPane error_pane = new ErrorPane();
        central_area_layouter.add(error_pane);
        central_area_layouter.show_all();

        active_pane = error_pane;
        
        close_cancel_button.set_label(_("Close"));
    }

    public void on_success() {
        central_area_layouter.remove(active_pane);

        SuccessPane success_pane = new SuccessPane();
        central_area_layouter.add(success_pane);
        central_area_layouter.show_all();

        active_pane = success_pane;
        
        close_cancel_button.set_label(_("Close"));
    }

    private void on_facebook_login_failed() {
        central_area_layouter.remove(active_pane);
        FacebookConnector.NotLoggedInPane not_logged_in_pane =
            new FacebookConnector.NotLoggedInPane();
        not_logged_in_pane.login_requested += on_login_requested;
        central_area_layouter.add(not_logged_in_pane);
        central_area_layouter.show_all();

        active_pane = not_logged_in_pane;
    }
    
    private void on_facebook_login_error() {
        on_error();
    }

    private void on_facebook_login_success(FacebookConnector.Session session) {
        facebook_session = session;
        Config config = Config.get_instance();
        config.set_facebook_session_key(session.get_session_key());
        config.set_facebook_session_secret(session.get_session_secret());
        config.set_facebook_uid(session.get_user_id());       
        config.set_facebook_user_name(session.get_user_name());

        central_area_layouter.remove(active_pane);
        FacebookConnector.UploadPane facebook_upload_pane =
            new FacebookConnector.UploadPane(facebook_session);
        facebook_upload_pane.logout += on_facebook_logout;
        facebook_upload_pane.publish += on_facebook_publish;
        central_area_layouter.add(facebook_upload_pane);
        central_area_layouter.show_all();

        active_pane = facebook_upload_pane;

        try {
            facebook_upload_pane.run_interaction();
        } catch (PublishingError e) {
            on_error();
        }
    }
    
    private void on_facebook_logout() {
        FacebookConnector.invalidate_persistent_session();

        if (FacebookConnector.LoginShell.get_is_cache_dirty()) {
            central_area_layouter.remove(active_pane);
            PublishingDialogPane restart_pane = new RestartMessagePane();
            central_area_layouter.add(restart_pane);
            central_area_layouter.show_all();
            
            active_pane = restart_pane;

            close_cancel_button.set_label(_("Close"));
        } else {
            central_area_layouter.remove(active_pane);
            FacebookConnector.NotLoggedInPane not_logged_in_pane =
                new FacebookConnector.NotLoggedInPane();
            not_logged_in_pane.login_requested += on_login_requested;
            central_area_layouter.add(not_logged_in_pane);
            central_area_layouter.show_all();

            active_pane = not_logged_in_pane;
        }
    }
    
    private void on_facebook_publish(string target_album_name) {
        central_area_layouter.remove(active_pane);
        ProgressPane progress_pane = new ProgressPane();
        central_area_layouter.add(progress_pane);
        central_area_layouter.show_all();
        active_pane = progress_pane;

        File temp_dir = AppDirs.get_temp_dir();

        FacebookConnector.Album[] albums = null;
        try {
            albums = FacebookConnector.get_albums(facebook_session);
        } catch (PublishingError e) {
            on_error();
        }

        string target_aid = null;
        foreach (FacebookConnector.Album album in albums) {
            if (album.name == target_album_name)
                target_aid = album.id;
        }
        if (target_aid == null) {
            try {
                target_aid = FacebookConnector.create_album(facebook_session, target_album_name);
            } catch (PublishingError e) {
                on_error();
            }
        }

        progress_pane.set_status_text(_("Preparing photos for upload"));
        spin_event_loop();

        int current_file_num = 0;
        File[] temp_files = new File[0];
        foreach (DataView view in target_collection) {
            if (user_cancelled)
                break;

            TransformablePhoto photo = (TransformablePhoto) view.get_source();
            File current_temp_file = temp_dir.get_child(TEMP_FILE_PREFIX +
                ("%d".printf(current_file_num)) + ".jpg");
            try {
                photo.export(current_temp_file, FacebookConnector.MAX_PHOTO_DIMENSION,
                    ScaleConstraint.DIMENSIONS, Jpeg.Quality.MAXIMUM);
            } catch (Error e) {
                error("Facebook Publishing: can't create temporary files");
            }

            current_file_num++;
            temp_files += current_temp_file;
            
            double phase_fraction_complete = ((double) current_file_num) / ((double) num_items);
            double fraction_complete = phase_fraction_complete * 0.3;
            progress_pane.set_progress(fraction_complete);
            spin_event_loop();
        }

        current_file_num = 0;
        foreach (File current_temp_file in temp_files) {
            if (user_cancelled)
                break;

            progress_pane.set_status_text(_("Uploading photo %d of %d").printf(current_file_num + 1,
                num_items));
            spin_event_loop();

            FacebookConnector.PhotoUploadRequest upload_req =
                new FacebookConnector.PhotoUploadRequest(facebook_session, target_aid,
                current_temp_file.get_path());
            upload_req.execute();
            try {
                current_temp_file.delete(null);
            } catch (Error e) {
                // if deleting temporary files generates an exception, just print a warning
                // message -- temp directory clean-up will be done on launch or at exit or
                // both
                warning("Facebook Publishing: deleting temporary files failed.");
            }
            
            current_file_num++;

            double phase_fraction_complete = ((double) current_file_num) / ((double) num_items);
            double fraction_complete = 0.3 + phase_fraction_complete * 0.7;
            progress_pane.set_progress(fraction_complete);
        }
        
        user_cancelled = false;
        
        on_success();
    }

    public static PublishingDialog get_active_instance() {
        return active_instance;
    }
}

#endif
