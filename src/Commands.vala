/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// PageCommand stores the current page when a Command is created.  Subclasses can call return_to_page()
// if it's appropriate to return to that page when executing an undo() or redo().
public abstract class PageCommand : Command {
    private Page? page;
    private bool auto_return = true;
    
    public PageCommand(string name, string explanation) {
        base (name, explanation);
        
        page = AppWindow.get_instance().get_current_page();
        if (page != null)
            page.destroy += on_page_destroyed;
    }
    
    ~PageCommand() {
        if (page != null)
            page.destroy -= on_page_destroyed;
    }
    
    public void set_auto_return_to_page(bool auto_return) {
        this.auto_return = auto_return;
    }
    
    public override void prepare() {
        if (auto_return)
            return_to_page();
        
        base.prepare();
    }
    
    public void return_to_page() {
        if (page != null)
            AppWindow.get_instance().set_current_page(page);
    }
    
    private void on_page_destroyed() {
        page.destroy -= on_page_destroyed;
        page = null;
    }
}

public abstract class SingleDataSourceCommand : PageCommand {
    protected DataSource source;
    
    public SingleDataSourceCommand(DataSource source, string name, string explanation) {
        base(name, explanation);
        
        this.source = source;
        
        source.destroyed += on_source_destroyed;
    }
    
    ~SingleDataSourceCommand() {
        source.destroyed -= on_source_destroyed;
    }
    
    public DataSource get_source() {
        return source;
    }
    
    private void on_source_destroyed() {
        // too much risk in simply removing this from the CommandManager; if this is considered too
        // broad a brushstroke, can return to this later
        get_command_manager().reset();
    }
}

public abstract class SinglePhotoTransformationCommand : SingleDataSourceCommand {
    private PhotoTransformationState state;
    
    public SinglePhotoTransformationCommand(TransformablePhoto photo, string name, string explanation) {
        base(photo, name, explanation);
        
        state = photo.save_transformation_state();
    }
    
    public override void undo() {
        ((TransformablePhoto) source).load_transformation_state(state);
    }
}

public abstract class GenericPhotoTransformationCommand : SingleDataSourceCommand {
    private PhotoTransformationState original_state = null;
    private PhotoTransformationState transformed_state = null;
    
    public GenericPhotoTransformationCommand(TransformablePhoto photo, string name, string explanation) {
        base(photo, name, explanation);
    }
    
    public override void execute() {
        TransformablePhoto photo = (TransformablePhoto) source;
        
        original_state = photo.save_transformation_state();
        
        execute_on_photo(photo);
        
        transformed_state = photo.save_transformation_state();
    }
    
    public abstract void execute_on_photo(TransformablePhoto photo);
    
    public override void undo() {
        // use the original state of the photo
        ((TransformablePhoto) source).load_transformation_state(original_state);
    }
    
    public override void redo() {
        // use the state of the photo after transformation
        ((TransformablePhoto) source).load_transformation_state(transformed_state);
    }
    
    protected virtual bool can_compress(Command command) {
        return false;
    }
    
    public override bool compress(Command command) {
        if (!can_compress(command))
            return false;
        
        GenericPhotoTransformationCommand generic = command as GenericPhotoTransformationCommand;
        if (generic == null)
            return false;
        
        if (generic.source != source)
            return false;
        
        // execute this new (and successive) command
        generic.execute();
        
        // save it's new transformation state as ours
        transformed_state = generic.transformed_state;
        
        return true;
    }
}

public abstract class MultipleDataSourceCommand : PageCommand {
    protected const int MIN_OPS_FOR_PROGRESS_WINDOW = 5;
    
    protected Gee.ArrayList<DataSource> source_list = new Gee.ArrayList<DataSource>();
    
    private string progress_text;
    private string undo_progress_text;
    private SourceCollection collection = null;
    private Gee.ArrayList<DataSource> acted_upon = new Gee.ArrayList<DataSource>();
    
    public MultipleDataSourceCommand(Gee.Iterable<DataView> iter, string progress_text,
        string undo_progress_text, string name, string explanation) {
        base(name, explanation);
        
        this.progress_text = progress_text;
        this.undo_progress_text = undo_progress_text;
        
        foreach (DataView view in iter) {
            DataSource source = view.get_source();
            
            // all DataSources must be a part of the same collection
            if (collection == null) {
                collection = (SourceCollection) source.get_membership();
            } else {
                assert(collection == source.get_membership());
            }
            
            source_list.add(source);
        }
        
        if (collection != null)
            collection.item_destroyed += on_source_destroyed;
    }
    
    ~MultipleDataSourceCommand() {
        if (collection != null)
            collection.item_destroyed -= on_source_destroyed;
    }
    
    public Gee.Iterable<DataSource> get_sources() {
        return source_list;
    }
    
    public int get_source_count() {
        return source_list.size;
    }
    
    private void on_source_destroyed(DataSource source) {
        // as with SingleDataSourceCommand, too risky to selectively remove commands from the stack,
        // although this could be reconsidered in the future
        if (source_list.contains(source))
            get_command_manager().reset();
    }
    
    public override void execute() {
        acted_upon.clear();
        execute_all(true, true, source_list, acted_upon);
    }
    
    public abstract void execute_on_source(DataSource source);
    
    public override void undo() {
        if (acted_upon.size > 0) {
            execute_all(false, false, acted_upon, null);
            acted_upon.clear();
        }
    }
    
    public abstract void undo_on_source(DataSource source);
    
    private void execute_all(bool exec, bool can_cancel, Gee.ArrayList<DataSource> todo, 
        Gee.ArrayList<DataSource>? completed) {
        AppWindow.get_instance().set_busy_cursor();
        
        int count = 0;
        int total = todo.size;
        
        string text = exec ? progress_text : undo_progress_text;
        
        Cancellable cancellable = null;
        ProgressDialog progress = null;
        if (total >= MIN_OPS_FOR_PROGRESS_WINDOW) {
            cancellable = can_cancel ? new Cancellable() : null;
            progress = new ProgressDialog(AppWindow.get_instance(), text, cancellable);
        }
        
        foreach (DataSource source in todo) {
            if (exec)
                execute_on_source(source);
            else
                undo_on_source(source);
            
            if (completed != null)
                completed.add(source);

            if (progress != null) {
                progress.set_fraction(++count, total);
                spin_event_loop();
                
                if (cancellable != null && cancellable.is_cancelled())
                    break;
            }
        }
        
        if (progress != null)
            progress.close();
        
        AppWindow.get_instance().set_normal_cursor();
    }
}

public abstract class MultiplePhotoTransformationCommand : MultipleDataSourceCommand {
    private Gee.HashMap<TransformablePhoto, PhotoTransformationState> map = new Gee.HashMap<
        TransformablePhoto, PhotoTransformationState>();
    
    public MultiplePhotoTransformationCommand(Gee.Iterable<DataView> iter, string progress_text,
        string undo_progress_text, string name, string explanation) {
        base(iter, progress_text, undo_progress_text, name, explanation);
        
        foreach (DataSource source in source_list) {
            TransformablePhoto photo = (TransformablePhoto) source;
            map.set(photo, photo.save_transformation_state());
        }
    }
    
    public override void undo_on_source(DataSource source) {
        TransformablePhoto photo = (TransformablePhoto) source;
        
        PhotoTransformationState state = map.get(photo);
        assert(state != null);
        
        photo.load_transformation_state(state);
    }
}

public class RotateSingleCommand : SingleDataSourceCommand {
    private Rotation rotation;
    
    public RotateSingleCommand(TransformablePhoto photo, Rotation rotation, string name, string explanation) {
        base(photo, name, explanation);
        
        this.rotation = rotation;
    }
    
    public override void execute() {
        ((TransformablePhoto) source).rotate(rotation);
    }
    
    public override void undo() {
        ((TransformablePhoto) source).rotate(rotation.opposite());
    }
}

public class RotateMultipleCommand : MultipleDataSourceCommand {
    private Rotation rotation;
    
    public RotateMultipleCommand(Gee.Iterable<DataView> iter, Rotation rotation, string name, 
        string explanation, string progress_text, string undo_progress_text) {
        base(iter, progress_text, undo_progress_text, name, explanation);
        
        this.rotation = rotation;
    }
    
    public override void execute_on_source(DataSource source) {
        ((TransformablePhoto) source).rotate(rotation);
    }
    
    public override void undo_on_source(DataSource source) {
        ((TransformablePhoto) source).rotate(rotation.opposite());
    }
}

public class RenameEventCommand : SingleDataSourceCommand {
    private string new_name;
    private string? old_name;
    
    public RenameEventCommand(Event event, string new_name) {
        base(event, Resources.RENAME_EVENT_LABEL, Resources.RENAME_EVENT_TOOLTIP);
        
        this.new_name = new_name;
        old_name = event.get_raw_name();
    }
    
    public override void execute() {
        ((Event) source).rename(new_name);
    }
    
    public override void undo() {
        ((Event) source).rename(old_name);
    }
}

public class SetKeyPhotoCommand : SingleDataSourceCommand {
    private LibraryPhoto new_key_photo;
    private LibraryPhoto old_key_photo;
    
    public SetKeyPhotoCommand(Event event, LibraryPhoto new_key_photo) {
        base(event, Resources.MAKE_KEY_PHOTO_LABEL, Resources.MAKE_KEY_PHOTO_TOOLTIP);
        
        this.new_key_photo = new_key_photo;
        old_key_photo = event.get_primary_photo();
    }
    
    public override void execute() {
        ((Event) source).set_primary_photo(new_key_photo);
    }
    
    public override void undo() {
        ((Event) source).set_primary_photo(old_key_photo);
    }
}

public class RevertSingleCommand : GenericPhotoTransformationCommand {
    public RevertSingleCommand(TransformablePhoto photo) {
        base(photo, Resources.REVERT_LABEL, Resources.REVERT_TOOLTIP);
    }
    
    public override void execute_on_photo(TransformablePhoto photo) {
        photo.remove_all_transformations();
    }
    
    public override bool compress(Command command) {
        RevertSingleCommand revert_single_command = command as RevertSingleCommand;
        if (revert_single_command == null)
            return false;
        
        if (revert_single_command.source != source)
            return false;
        
        // no need to execute anything; multiple successive reverts on the same photo are as good
        // as one
        return true;
    }
}

public class RevertMultipleCommand : MultiplePhotoTransformationCommand {
    public RevertMultipleCommand(Gee.Iterable<DataView> iter) {
        base(iter, _("Reverting..."), _("Undoing Revert..."), Resources.REVERT_LABEL,
            Resources.REVERT_TOOLTIP);
    }
    
    public override void execute_on_source(DataSource source) {
        ((TransformablePhoto) source).remove_all_transformations();
    }
}

public class EnhanceSingleCommand : GenericPhotoTransformationCommand {
    public EnhanceSingleCommand(TransformablePhoto photo) {
        base(photo, Resources.ENHANCE_LABEL, Resources.ENHANCE_TOOLTIP);
    }
    
    public override void execute_on_photo(TransformablePhoto photo) {
        AppWindow.get_instance().set_busy_cursor();
#if MEASURE_ENHANCE
        Timer overall_timer = new Timer();
#endif
        
        photo.enhance();
        
#if MEASURE_ENHANCE
        overall_timer.stop();
        debug("Auto-Enhance overall time: %f sec", overall_timer.elapsed());
#endif
        AppWindow.get_instance().set_normal_cursor();
    }
    
    public override bool compress(Command command) {
        EnhanceSingleCommand enhance_single_command = command as EnhanceSingleCommand;
        if (enhance_single_command == null)
            return false;
        
        if (enhance_single_command.source != source)
            return false;
        
        // multiple successive enhances on the same photo are as good as a single
        return true;
    }
}

public class EnhanceMultipleCommand : MultiplePhotoTransformationCommand {
    public EnhanceMultipleCommand(Gee.Iterable<DataView> iter) {
        base(iter, _("Enhancing..."), _("Undoing Enhance..."), Resources.ENHANCE_LABEL,
            Resources.ENHANCE_TOOLTIP);
    }
    
    public override void execute_on_source(DataSource source) {
        ((TransformablePhoto) source).enhance();
    }
}

public class CropCommand : GenericPhotoTransformationCommand {
    private Box crop;
    
    public CropCommand(TransformablePhoto photo, Box crop, string name, string explanation) {
        base(photo, name, explanation);
        
        this.crop = crop;
    }
    
    public override void execute_on_photo(TransformablePhoto photo) {
        photo.set_crop(crop);
    }
}

public class AdjustColorsCommand : GenericPhotoTransformationCommand {
    private PixelTransformationBundle transformations;
    
    public AdjustColorsCommand(TransformablePhoto photo, PixelTransformationBundle transformations,
        string name, string explanation) {
        base(photo, name, explanation);
        
        this.transformations = transformations;
    }
    
    public override void execute_on_photo(TransformablePhoto photo) {
        AppWindow.get_instance().set_busy_cursor();
        
        photo.set_color_adjustments(transformations);
        
        AppWindow.get_instance().set_normal_cursor();
    }
    
    public override bool can_compress(Command command) {
        return command is AdjustColorsCommand;
    }
}

public class RedeyeCommand : GenericPhotoTransformationCommand {
    private RedeyeInstance redeye_instance;
    
    public RedeyeCommand(TransformablePhoto photo, RedeyeInstance redeye_instance, string name,
        string explanation) {
        base(photo, name, explanation);
        
        this.redeye_instance = redeye_instance;
    }
    
    public override void execute_on_photo(TransformablePhoto photo) {
        photo.add_redeye_instance(redeye_instance);
    }
}

public abstract class MovePhotosCommand : Command {
    // Piggyback on a private command so that processing to determine new_event can occur before
    // contruction, if needed
    protected class RealMovePhotosCommand : MultipleDataSourceCommand {
        private SourceProxy new_event_proxy = null;
        private Gee.HashMap<LibraryPhoto, SourceProxy?> old_photo_events = new Gee.HashMap<
            LibraryPhoto, SourceProxy?>();
        
        public RealMovePhotosCommand( Event? new_event, Gee.Iterable<DataView> photos,
            string progress_text, string undo_progress_text, string name, string explanation) {
            base(photos, progress_text, undo_progress_text, name, explanation);
            
            // get proxies for the photos' events
            foreach (DataSource source in source_list) {
                LibraryPhoto photo = (LibraryPhoto) source;
                Event? old_event = photo.get_event();
                SourceProxy? old_event_proxy = (old_event != null) ? old_event.get_proxy() : null;
                
                // if any of the proxies break, the show's off
                if (old_event_proxy != null)
                    old_event_proxy.broken += on_proxy_broken;
                
                old_photo_events.set(photo, old_event_proxy);
            }
            
            // stash the proxy of the new event
            new_event_proxy = new_event.get_proxy();
            new_event_proxy.broken += on_proxy_broken;
        }
        
        ~RealMovePhotosCommand() {
            new_event_proxy.broken -= on_proxy_broken;
            
            foreach (SourceProxy? proxy in old_photo_events.values) {
                if (proxy != null)
                    proxy.broken -= on_proxy_broken;
            }
        }
        
        public override void execute() {
            // switch to new event page first (to prevent flicker if other pages are destroyed)
            LibraryWindow.get_app().switch_to_event((Event) new_event_proxy.get_source());
            
            // create the new event
            base.execute();
        }
        
        public override void execute_on_source(DataSource source) {
            ((LibraryPhoto) source).set_event((Event?) new_event_proxy.get_source());
        }
        
        public override void undo_on_source(DataSource source) {
            LibraryPhoto photo = (LibraryPhoto) source;
            SourceProxy? event_proxy = old_photo_events.get(photo);
            
            photo.set_event(event_proxy != null ? (Event?) event_proxy.get_source() : null);
        }
        
        private void on_proxy_broken() {
            get_command_manager().reset();
        }
    }

    protected RealMovePhotosCommand real_command;
    
    public MovePhotosCommand(string name, string explanation) {
        base(name, explanation);
    }
    
    public override void prepare() {
        assert(real_command != null);
        real_command.prepare();
    }
    
    public override void execute() {
        assert(real_command != null);
        real_command.execute();
    }
    
    public override void undo() {
        assert(real_command != null);
        real_command.undo();
    }
}

public class NewEventCommand : MovePhotosCommand {   
    public NewEventCommand(Gee.Iterable<DataView> iter) {       
        base(Resources.NEW_EVENT_LABEL, Resources.NEW_EVENT_TOOLTIP);

        // get the key photo for the new event (which is simply the first one)
        LibraryPhoto key_photo = null;
        foreach (DataView view in iter) {
            LibraryPhoto photo = (LibraryPhoto) view.get_source();;
            
            if (key_photo == null) {
                key_photo = photo;
                break;
            }
        }
        
        // key photo is required for an event
        assert(key_photo != null);

        Event new_event = Event.create_empty_event(key_photo);

        real_command = new RealMovePhotosCommand(new_event, iter, _("Creating New Event..."),
            _("Removing Event..."), Resources.NEW_EVENT_LABEL,
            Resources.NEW_EVENT_TOOLTIP);        
    }
}

public class SetEventCommand : MovePhotosCommand {   
    public SetEventCommand(Gee.Iterable<DataView> iter, Event new_event) {
        base(Resources.SET_PHOTO_EVENT_LABEL, Resources.SET_PHOTO_EVENT_TOOLTIP);

        real_command = new RealMovePhotosCommand(new_event, iter, _("Moving Photos to New Event..."),
            _("Setting Photos to Previous Event..."), Resources.SET_PHOTO_EVENT_LABEL, 
            Resources.SET_PHOTO_EVENT_TOOLTIP);
    }
}

public class MergeEventsCommand : MovePhotosCommand {
    public MergeEventsCommand(Gee.Iterable<DataView> iter) {
        base (Resources.MERGE_LABEL, Resources.MERGE_TOOLTIP);
        
        // the master event is the first one found with a name, otherwise the first one in the lot
        Event master_event = null;
        Gee.ArrayList<PhotoView> photos = new Gee.ArrayList<PhotoView>();
        
        foreach (DataView view in iter) {
            Event event = (Event) view.get_source();
            
            if (master_event == null)
                master_event = event;
            else if (!master_event.has_name() && event.has_name())
                master_event = event;
            
            // store all photos in this operation; they will be moved to the master event
            // (keep proxies of their original event for undo)
            foreach (PhotoSource photo_source in event.get_photos())
                photos.add(new PhotoView(photo_source));
        }
        
        assert(master_event != null);
        assert(photos.size > 0);
        
        real_command = new RealMovePhotosCommand(master_event, photos, _("Merging..."), 
            _("Unmerging..."), Resources.MERGE_LABEL, Resources.MERGE_TOOLTIP);
    }
}

public class DuplicateMultiplePhotosCommand : MultipleDataSourceCommand {
    private Gee.HashMap<LibraryPhoto, LibraryPhoto> dupes = new Gee.HashMap<LibraryPhoto, LibraryPhoto>();
    private int failed = 0;
    
    public DuplicateMultiplePhotosCommand(Gee.Iterable<DataView> iter) {
        base (iter, _("Duplicating photos..."), _("Removing duplicated photos..."), 
            Resources.DUPLICATE_PHOTO_LABEL, Resources.DUPLICATE_PHOTO_TOOLTIP);
        
        LibraryPhoto.global.item_destroyed += on_photo_destroyed;
    }
    
    ~DuplicateMultiplePhotosCommand() {
        LibraryPhoto.global.item_destroyed -= on_photo_destroyed;
    }
    
    private void on_photo_destroyed(DataSource source) {
        // if one of the duplicates is destroyed, can no longer undo it (which destroys it again)
        if (dupes.values.contains((LibraryPhoto) source))
            get_command_manager().reset();
    }
    
    public override void execute() {
        dupes.clear();
        failed = 0;
        
        base.execute();
        
        if (failed > 0) {
            string error_string = (ngettext("Unable to duplicate one photo due to a file error",
                "Unable to duplicate %d photos due to file errors", failed)).printf(failed);
            AppWindow.error_message(error_string);
        }
    }
    
    public override void execute_on_source(DataSource source) {
        LibraryPhoto photo = (LibraryPhoto) source;
        
        try {
            LibraryPhoto dupe = photo.duplicate();
            dupes.set(photo, dupe);
        } catch (Error err) {
            critical("Unable to duplicate file %s: %s", photo.get_file().get_path(), err.message);
            failed++;
        }
    }
    
    public override void undo() {
        // disconnect from monitoring the duplicates' destruction, as undo() does exactly that
        LibraryPhoto.global.item_destroyed -= on_photo_destroyed;
        
        base.undo();
        
        // be sure to drop everything that was destroyed
        dupes.clear();
        failed = 0;
        
        // re-monitor for duplicates' destruction
        LibraryPhoto.global.item_destroyed += on_photo_destroyed;
    }
    
    public override void undo_on_source(DataSource source) {
        LibraryPhoto photo = (LibraryPhoto) source;
        
        LibraryPhoto dupe = dupes.get(photo);
        dupe.delete_original_on_destroy();
        
        Marker marker = LibraryPhoto.global.mark(dupe);
        LibraryPhoto.global.destroy_marked(marker);
    }
}

public class FavoriteUnfavoriteCommand : MultipleDataSourceCommand {
    private bool favorite;
    
    public FavoriteUnfavoriteCommand(Gee.Iterable<DataView> iter, bool favorite) {
        base (iter,
            favorite ? _("Marking as Favorite...") : _("Unmarking as Favorite..."),
            favorite ? _("Unmarking as Favorite...") : _("Marking as Favorite..."),
            favorite ? Resources.FAVORITE_LABEL : Resources.UNFAVORITE_LABEL,
            favorite ? Resources.FAVORITE_TOOLTIP : Resources.UNFAVORITE_TOOLTIP);
        
        this.favorite = favorite;
    }
    
    public override void execute_on_source(DataSource source) {
        ((LibraryPhoto) source).set_favorite(favorite);
    }
    
    public override void undo_on_source(DataSource source) {
        ((LibraryPhoto) source).set_favorite(!favorite);
    }
}

public class HideUnhideCommand : MultipleDataSourceCommand {
    private bool hide;
    
    public HideUnhideCommand(Gee.Iterable<DataView> iter, bool hide) {
        base (iter,
            hide ? _("Hiding...") : _("Unhiding..."),
            hide ? _("Unhiding...") : _("Hiding..."),
            hide ? Resources.HIDE_LABEL : Resources.UNHIDE_LABEL,
            hide ? Resources.HIDE_TOOLTIP : Resources.UNHIDE_TOOLTIP);
        
        this.hide = hide;
    }
    
    public override void execute_on_source(DataSource source) {
        ((LibraryPhoto) source).set_hidden(hide);
    }
    
    public override void undo_on_source(DataSource source) {
        ((LibraryPhoto) source).set_hidden(!hide);
    }
}

