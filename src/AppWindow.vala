/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

// AppWindow is the parent window for most windows in Shotwell (FullscreenWindow is the exception).
// There are multiple types of AppWindows (LibraryWindow, DirectWindow) for different tasks, but only 
// one AppWindow may exist per process.  Thus, if the user closes an AppWindow, the program exits.
//
// AppWindow also offers support for going into fullscreen mode.  It handles the interface
// notifications Page is expecting when switching back and forth.
public abstract class AppWindow : PageWindow {
    public const int DND_ICON_SCALE = 128;
    
    protected static AppWindow instance = null;
    
    private static FullscreenWindow fullscreen_window = null;
    private static CommandManager command_manager = null;
    private Gtk.ShortcutController shortcut_controller = new Gtk.ShortcutController();

    private Gtk.Box content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
    private Gtk.PopoverMenuBar menu_bar;
    private Gtk.Revealer menu_revealer = new Gtk.Revealer();
    
    // the AppWindow maintains its own UI manager because the first UIManager an action group is
    // added to is the one that claims its accelerators
    protected Dimensions dimensions;
    protected int pos_x = 0;
    protected int pos_y = 0;
    
    public new void set_child(Gtk.Widget child) {
        content_box.append(child);
    }

    private void extract_accels_from_menu_item (GLib.MenuModel model, int item, Gtk.ShortcutController controller) {
        var iter = model.iterate_item_attributes (item);
        string key;
        Variant value;
        Gtk.ShortcutAction? action = null;
        Gtk.ShortcutTrigger? trigger = null;
        while (iter.get_next(out key, out value)) {
            if (key == "action") {
                action = new Gtk.NamedAction(value.get_string());
            } else if (key == "accel") {
                trigger = Gtk.ShortcutTrigger.parse_string(value.get_string());
            }
        }

        if (action != null && trigger != null) {
            controller.add_shortcut(new Gtk.Shortcut(trigger, action));
        }
    }

    private void get_accels_from_menu (GLib.MenuModel model, Gtk.ShortcutController controller) {
        for (var i = 0; i < model.get_n_items(); i++) {
            extract_accels_from_menu_item (model, i, controller);
            GLib.MenuModel sub_model;

            var iter = model.iterate_item_links (i);
            while (iter.get_next(null, out sub_model)) {
                get_accels_from_menu (sub_model, controller);
            }
        }
    }

    private Gtk.ShortcutController? menu_shortcuts = null;
    public void set_menubar(GLib.MenuModel? menu_model) {
        // Unregister the old shortcuts
        if (menu_shortcuts != null) {
            ((Gtk.Widget)this).remove_controller(menu_shortcuts);
            menu_shortcuts = null;
        }

        // TODO: Obey Gtk.Settings:gtk-shell-shows-menubar
        if (menu_model == null) {
            menu_revealer.set_reveal_child(false);
            menu_revealer.set_child(null);
            menu_bar = null;

            return;
        }

        // Collect shortcuts from menu
        menu_shortcuts = new Gtk.ShortcutController();
        get_accels_from_menu(menu_model, menu_shortcuts);
        menu_bar = new Gtk.PopoverMenuBar.from_model(menu_model);
        menu_revealer.set_child(menu_bar);
        menu_revealer.set_reveal_child(true);
        ((Gtk.Widget)this).add_controller(menu_shortcuts);
    }

    protected AppWindow() {
        base();

        menu_revealer.vexpand = false;
        menu_revealer.hexpand = true;
        content_box.append(menu_revealer);
        base.set_child(content_box);

        // although there are multiple AppWindow types, only one may exist per-process
        assert(instance == null);
        instance = this;

        title = Resources.APP_TITLE;
        set_default_icon_name("org.gnome.Shotwell");

        // restore previous size and maximization state

        bool was_maximized;
        if (this is LibraryWindow) {
            Config.Facade.get_instance().get_library_window_state(out was_maximized, out dimensions);
        } else {
            assert(this is DirectWindow);
            Config.Facade.get_instance().get_direct_window_state(out was_maximized, out dimensions);
        }

        set_default_size(dimensions.width, dimensions.height);

        if (was_maximized)
            maximize();

        assert(command_manager == null);
        command_manager = new CommandManager();
        command_manager.altered.connect(on_command_manager_altered);
        
        // Because the first UIManager to associated with an ActionGroup claims the accelerators,
        // need to create the AppWindow's ActionGroup early on and add it to an application-wide
        // UIManager.  In order to activate those accelerators, we need to create a dummy UI string
        // that lists all the common actions.  We build it on-the-fly from the actions associated
        // with each ActionGroup while we're adding the groups to the UIManager.

        add_actions ();

        notify["maximized"].connect(on_maximized);
    }

    private const GLib.ActionEntry[] common_actions = {
        { "CommonAbout", on_about },
        { "CommonQuit", on_quit },
        { "CommonFullscreen", on_fullscreen },
        { "CommonHelpContents", on_help_contents },
        { "CommonHelpFAQ", on_help_faq },
        { "CommonHelpReportProblem", on_help_report_problem },
        { "CommonUndo", on_undo },
        { "CommonRedo", on_redo },
        { "CommonJumpToFile", on_jump_to_file },
        { "CommonSelectAll", on_select_all },
        { "CommonSelectNone", on_select_none }
    };

    protected abstract void on_fullscreen();
    
    public static bool has_instance() {
        return instance != null;
    }
    
    public static AppWindow get_instance() {
        return instance;
    }

    public static FullscreenWindow get_fullscreen() {
        return fullscreen_window;
    }

    public static void error_message(string message, Gtk.Window? parent = null) {
        error_message_with_title(Resources.APP_TITLE, message, parent);
    }
    
    public static void error_message_with_title(string title, string message, Gtk.Window? parent = null, bool should_escape = true) {
        // Per the Gnome HIG (http://library.gnome.org/devel/hig-book/2.32/windows-alert.html.en),            
        // alert-style dialogs mustn't have titles; we use the title as the primary text, and the
        // existing message as the secondary text.
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", build_alert_body_text(title, message, should_escape));
            
        // Occasionally, with_markup doesn't actually do anything, but set_markup always works.
        dialog.set_markup(build_alert_body_text(title, message, should_escape));
        dialog.set_transient_for(parent != null ? parent : get_instance());

        dialog.use_markup = true;
        dialog.show();
        dialog.response.connect(() => dialog.destroy());
    }
    
    public static async bool negate_affirm_question(string message, string negative, string affirmative,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", build_alert_body_text(title, message));

        dialog.set_markup(build_alert_body_text(title, message));
        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES);
        
        dialog.show();

        int response_id = 0;
        SourceFunc callback = negate_affirm_question.callback;
        dialog.response.connect((source, resp) => {
            response_id = resp;
            dialog.destroy();
            callback();
        });
        yield;

        return response_id == Gtk.ResponseType.YES;
    }

    public static Gtk.ResponseType negate_affirm_cancel_question(string message, string negative,
        string affirmative, string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", build_alert_body_text(title, message));

        dialog.add_buttons(negative, Gtk.ResponseType.NO, affirmative, Gtk.ResponseType.YES,
            _("_Cancel"), Gtk.ResponseType.CANCEL);
        
        // Occasionally, with_markup doesn't actually enable markup, but set_markup always works.
        dialog.set_markup(build_alert_body_text(title, message));
        dialog.use_markup = true;

        int response = 0; //dialog.run();
        
        dialog.destroy();
        
        return (Gtk.ResponseType) response;
    }
    
    public static Gtk.ResponseType affirm_cancel_question(string message, string affirmative,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog.with_markup((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        // Occasionally, with_markup doesn't actually enable markup...? Force the issue.
        dialog.set_markup(message);
        dialog.use_markup = true;
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        dialog.add_buttons(affirmative, Gtk.ResponseType.YES, _("_Cancel"),
            Gtk.ResponseType.CANCEL);
        
        dialog.show();
        //int response = dialog.run();
        int response = Gtk.ResponseType.OK;
        
        dialog.destroy();
        
        return (Gtk.ResponseType) response;
    }
    
	public static int export_overwrite_or_replace_question(string message,
		string alt1, string alt2, string alt3, string alt4, string alt5, string alt6,
        string? title = null, Gtk.Window? parent = null) {
        Gtk.MessageDialog dialog = new Gtk.MessageDialog((parent != null) ? parent : get_instance(),
            Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s", message);
        dialog.title = (title != null) ? title : Resources.APP_TITLE;
        dialog.add_buttons(alt1, 1, alt2, 2, alt3, 3, alt4, 4, alt5, 5, alt6, 6);
        
        int response = Gtk.ResponseType.CANCEL;//dialog.run();
        
        dialog.destroy();
        
        return response;
    }

    public static void database_error(Error err) {
        panic(_("A fatal error occurred when accessing Shotwell’s library. Shotwell cannot continue.\n\n%s").printf(
            err.message));
    }

    public static void panic(string msg) {
        critical(msg);
        error_message(msg);
        
        Application.get_instance().panic();
    }
    
    public abstract string get_app_role();

    protected void on_about() {
        var hash = "";
        if (Resources.GIT_VERSION != "") {
            hash = " (%s)".printf(Resources.GIT_VERSION.substring(0,7));
        }
        string[] artists = {"Image of the Delmenhorst Town Hall by Charlie1965nrw, source: https://commons.wikimedia.org/wiki/File:Delmenhorst_Rathaus.jpg", null};
        Gtk.show_about_dialog(this,
            "version", Resources.APP_VERSION + hash + " — Delmenhorst",
            "comments", get_app_role(),
            "copyright", Resources.COPYRIGHT,
            "website", Resources.HOME_URL,
            "license", Resources.LICENSE,
            "website-label", _("Visit the Shotwell web site"),
            "authors", Resources.AUTHORS,
            "logo-icon-name", "shotwell",
            "translator-credits", _("translator-credits"),
            "artists", artists,
            null
        );
    }

    private void on_help_contents() {
        try {
            Resources.launch_help(this);
        } catch (Error err) {
            error_message(_("Unable to display help: %s").printf(err.message));
        }
    }

    private void on_help_report_problem() {
        try {
            show_uri(Resources.BUG_DB_URL);
        } catch (Error err) {
            error_message(_("Unable to navigate to bug database: %s").printf(err.message));
        }
    }
    
    private void on_help_faq() {
        try {
            show_uri(Resources.FAQ_URL);
        } catch (Error err) {
            error_message(_("Unable to display FAQ: %s").printf(err.message));
        }
    }
    
    protected virtual void on_quit() {
        Application.get_instance().exit();
    }

    protected void on_jump_to_file() {
        if (get_current_page().get_view().get_selected_count() != 1)
            return;

        MediaSource? media = get_current_page().get_view().get_selected_at(0).get_source()
            as MediaSource;
        if (media == null)
            return;
        
        try {
           AppWindow.get_instance().show_file_uri(media.get_master_file());
        } catch (Error err) {
            AppWindow.error_message(Resources.jump_to_file_failed(err));
        }
    }
    
    protected override bool close_request() {
        on_quit();

        return false;
    }
    
    public void show_file_uri(File file) throws Error {
        show_file_in_filemanager.begin(file);
    }
    
    public void show_uri(string url) throws Error {
        Gtk.show_uri(this, url, Gdk.CURRENT_TIME);
    }
    
    protected virtual void add_actions () {
        this.add_action_entries (AppWindow.common_actions, this);
    }

    public void go_fullscreen(Page page) {
        // if already fullscreen, use that
        if (fullscreen_window != null) {
            fullscreen_window.present();
            
            return;
        }

        //get_position(out pos_x, out pos_y);
        hide();
        
        FullscreenWindow fsw = new FullscreenWindow(page);
        
        if (get_current_page() != null)
            get_current_page().switching_to_fullscreen(fsw);
        
        fullscreen_window = fsw;
        fullscreen_window.present();
    }
    
    public void end_fullscreen() {
        if (fullscreen_window == null)
            return;
        
        //move(pos_x, pos_y);

        show();
        
        if (get_current_page() != null)
            get_current_page().returning_from_fullscreen(fullscreen_window);
        
        fullscreen_window.hide();
        fullscreen_window.destroy();
        fullscreen_window = null;
        
        present();
    }
    
    public GLib.Action? get_common_action(string name) {
        return lookup_action (name);
    }
    
    public void set_common_action_sensitive(string name, bool sensitive) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    public void set_common_action_important(string name, bool important) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    public void set_common_action_visible(string name, bool visible) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action != null)
            action.set_enabled (sensitive);
    }
    
    protected override void switched_pages(Page? old_page, Page? new_page) {
        update_common_action_availability(old_page, new_page);
        
        if (old_page != null) {
            old_page.get_view().contents_altered.disconnect(on_update_common_actions);
            old_page.get_view().selection_group_altered.disconnect(on_update_common_actions);
            old_page.get_view().items_state_changed.disconnect(on_update_common_actions);
        }
        
        if (new_page != null) {
            new_page.get_view().contents_altered.connect(on_update_common_actions);
            new_page.get_view().selection_group_altered.connect(on_update_common_actions);
            new_page.get_view().items_state_changed.connect(on_update_common_actions);
            
            update_common_actions(new_page, new_page.get_view().get_selected_count(),
                new_page.get_view().get_count());
        }
        
        base.switched_pages(old_page, new_page);
    }
    
    // This is called when a Page is switched out and certain common actions are simply
    // unavailable for the new one.  This is different than update_common_actions() in that that
    // call is made when state within the Page has changed.
    protected virtual void update_common_action_availability(Page? old_page, Page? new_page) {
        bool is_checkerboard = new_page is CheckerboardPage;
        
        set_common_action_sensitive("CommonSelectAll", is_checkerboard);
        set_common_action_sensitive("CommonSelectNone", is_checkerboard);
    }
    
    // This is a counterpart to Page.update_actions(), but for common Gtk.Actions
    // NOTE: Although CommonFullscreen is declared here, it's implementation is up to the subclasses,
    // therefore they need to update its action.
    protected virtual void update_common_actions(Page page, int selected_count, int count) {
        if (page is CheckerboardPage)
            set_common_action_sensitive("CommonSelectAll", count > 0);
        set_common_action_sensitive("CommonJumpToFile", selected_count == 1);
        
        decorate_undo_action();
        decorate_redo_action();
    }
    
    private void on_update_common_actions() {
        Page? page = get_current_page();
        if (page != null)
            update_common_actions(page, page.get_view().get_selected_count(), page.get_view().get_count());
    }

    public void update_menu_item_label (string id,
                                         string new_label) {
        var bar = this.get_current_page().get_menubar() as GLib.Menu;

        if (bar == null) {
            return;
        }

        var items = bar.get_n_items ();
        for (var i = 0; i< items; i++) {
            var model = bar.get_item_link (i, GLib.Menu.LINK_SUBMENU);
            if (bar == null) {
                continue;
            }

            var model_items = model.get_n_items ();
            for (var j = 0; j < model_items; j++) {
                var subsection = model.get_item_link (j, GLib.Menu.LINK_SECTION);

                if (subsection == null)
                    continue;

                // Recurse into submenus
                var sub_items = subsection.get_n_items ();
                for (var k = 0; k < sub_items; k++) {
                    var it = subsection.iterate_item_attributes (k);
                    while (it.next ()) {
                        if ((it.get_name() == "id" && it.get_value ().get_string () == id) ||
                            (it.get_name() == "action" && it.get_value().get_string().has_suffix("." + id))) {
                            var md = subsection as GLib.Menu;
                            var m = new GLib.MenuItem.from_model (subsection, k);
                            m.set_label (new_label);
                            md.remove (k);
                            md.insert_item (k, m);

                            return;
                        }
                    }
                }
            }
        }
    }


    
    public static CommandManager get_command_manager() {
        return command_manager;
    }
    
    private void on_command_manager_altered() {
        decorate_undo_action();
        decorate_redo_action();
    }
    
    private void decorate_command_manager_action(string name, string prefix,
        string default_explanation, CommandDescription? desc) {
        var action = get_common_action(name) as GLib.SimpleAction;
        if (action == null) {
            return;
        }

        string label = prefix;

        if (desc != null) {
            label += " " + desc.get_name();
            action.set_enabled(true);
        } else {
            label = prefix;
            action.set_enabled(false);
        }
        this.update_menu_item_label(name, label);
    }
    
    public void decorate_undo_action() {
        decorate_command_manager_action("CommonUndo", Resources.UNDO_MENU, "",
            get_command_manager().get_undo_description());
    }
    
    public void decorate_redo_action() {
        decorate_command_manager_action("CommonRedo", Resources.REDO_MENU, "",
            get_command_manager().get_redo_description());
    }
    
    private void on_undo() {
        command_manager.undo();
    }
    
    private void on_redo() {
        command_manager.redo();
    }
    
    private void on_select_all() {
        Page? page = get_current_page() as CheckerboardPage;
        if (page != null)
            page.get_view().select_all();
    }
    
    private void on_select_none() {
        Page? page = get_current_page() as CheckerboardPage;
        if (page != null)
            page.get_view().unselect_all();
    }
    
    public void on_maximized() {
        if (!maximized) {
            dimensions.width = get_size (Gtk.Orientation.HORIZONTAL);
            dimensions.height = get_size (Gtk.Orientation.VERTICAL);
        }
    }
    
}

