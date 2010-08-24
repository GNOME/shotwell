/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// PageCommand stores the current page when a Command is created.  Subclasses can call return_to_page()
// if it's appropriate to return to that page when executing an undo() or redo().
public abstract class PageCommand : Command {
    private Page? page;
    private bool auto_return = true;
    private Photo library_photo = null;
    private CollectionPage collection_page = null;
    
    public PageCommand(string name, string explanation) {
        base (name, explanation);
        
        page = AppWindow.get_instance().get_current_page();
        
        if (page != null) {
            page.destroy.connect(on_page_destroyed);
            
            // If the command occurred on a LibaryPhotoPage, the PageCommand must record additional
            // objects to be restore it to its old state: a specific photo to focus on, a page to return 
            // to, and a view collection to operate over. Note that these objects can be cleared if 
            // the page goes into the background. The required objects are stored below.
            LibraryPhotoPage photo_page = page as LibraryPhotoPage;
            if (photo_page != null) {
                library_photo = photo_page.get_photo();
                collection_page = photo_page.get_controller_page();
                
                if (library_photo != null && collection_page != null) {
                    library_photo.destroyed.connect(on_photo_destroyed);
                    collection_page.destroy.connect(on_controller_destroyed);
                } else {
                    library_photo = null;
                    collection_page = null;
                }
            }
        }
    }
    
    ~PageCommand() {
        if (page != null)
            page.destroy.disconnect(on_page_destroyed);
        
        if (library_photo != null)
            library_photo.destroyed.disconnect(on_photo_destroyed);

        if (collection_page != null)
            collection_page.destroy.disconnect(on_controller_destroyed);
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
        LibraryPhotoPage photo_page = page as LibraryPhotoPage;  

        if (photo_page != null) { 
            if (library_photo != null && collection_page != null) {
                bool photo_in_collection = false;
                int count = collection_page.get_view().get_count();
                for (int i = 0; i < count; i++) {
                    if ( ((Thumbnail) collection_page.get_view().get_at(i)).get_photo() == library_photo) {
                        photo_in_collection = true;
                        break;
                    }
                }
                
                if (photo_in_collection)
                    LibraryWindow.get_app().switch_to_photo_page(collection_page, library_photo);
            }
        } else if (page != null)
            AppWindow.get_instance().set_current_page(page);
    }
    
    private void on_page_destroyed() {
        page.destroy.disconnect(on_page_destroyed);
        page = null;
    }
    
    private void on_photo_destroyed() {
        library_photo.destroyed.disconnect(on_photo_destroyed);
        library_photo = null;
    }

    private void on_controller_destroyed() {
        collection_page.destroy.disconnect(on_controller_destroyed);
        collection_page = null;
    }

}

public abstract class SingleDataSourceCommand : PageCommand {
    protected DataSource source;
    
    public SingleDataSourceCommand(DataSource source, string name, string explanation) {
        base(name, explanation);
        
        this.source = source;
        
        source.destroyed.connect(on_source_destroyed);
    }
    
    ~SingleDataSourceCommand() {
        source.destroyed.disconnect(on_source_destroyed);
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

public abstract class SimpleProxyableCommand : PageCommand {
    private SourceProxy proxy;
    
    public SimpleProxyableCommand(Proxyable proxyable, string name, string explanation) {
        base (name, explanation);
        
        proxy = proxyable.get_proxy();
        proxy.broken.connect(on_proxy_broken);
    }
    
    ~SimpleProxyableCommand() {
        proxy.broken.disconnect(on_proxy_broken);
    }
    
    public override void execute() {
        execute_on_source(proxy.get_source());
    }
    
    protected abstract void execute_on_source(DataSource source);
    
    public override void undo() {
        undo_on_source(proxy.get_source());
    }
    
    protected abstract void undo_on_source(DataSource source);
    
    private void on_proxy_broken() {
        get_command_manager().reset();
    }
}

public abstract class SinglePhotoTransformationCommand : SingleDataSourceCommand {
    private PhotoTransformationState state;
    
    public SinglePhotoTransformationCommand(Photo photo, string name, string explanation) {
        base(photo, name, explanation);
        
        state = photo.save_transformation_state();
        state.broken.connect(on_state_broken);
    }
    
    ~SinglePhotoTransformationCommand() {
        state.broken.disconnect(on_state_broken);
    }
    
    public override void undo() {
        ((Photo) source).load_transformation_state(state);
    }
    
    private void on_state_broken() {
        get_command_manager().reset();
    }
}

public abstract class GenericPhotoTransformationCommand : SingleDataSourceCommand {
    private PhotoTransformationState original_state = null;
    private PhotoTransformationState transformed_state = null;
    
    public GenericPhotoTransformationCommand(Photo photo, string name, string explanation) {
        base(photo, name, explanation);
    }
    
    ~GenericPhotoTransformationState() {
        if (original_state != null)
            original_state.broken.disconnect(on_state_broken);
        
        if (transformed_state != null)
            transformed_state.broken.disconnect(on_state_broken);
    }
    
    public override void execute() {
        Photo photo = (Photo) source;
        
        original_state = photo.save_transformation_state();
        original_state.broken.connect(on_state_broken);
        
        execute_on_photo(photo);
        
        transformed_state = photo.save_transformation_state();
        transformed_state.broken.connect(on_state_broken);
    }
    
    public abstract void execute_on_photo(Photo photo);
    
    public override void undo() {
        // use the original state of the photo
        ((Photo) source).load_transformation_state(original_state);
    }
    
    public override void redo() {
        // use the state of the photo after transformation
        ((Photo) source).load_transformation_state(transformed_state);
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
    
    private void on_state_broken() {
        get_command_manager().reset();
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
            collection.item_destroyed.connect(on_source_destroyed);
    }
    
    ~MultipleDataSourceCommand() {
        if (collection != null)
            collection.item_destroyed.disconnect(on_source_destroyed);
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
    private Gee.HashMap<Photo, PhotoTransformationState> map = new Gee.HashMap<
        Photo, PhotoTransformationState>();
    
    public MultiplePhotoTransformationCommand(Gee.Iterable<DataView> iter, string progress_text,
        string undo_progress_text, string name, string explanation) {
        base(iter, progress_text, undo_progress_text, name, explanation);
        
        foreach (DataSource source in source_list) {
            Photo photo = (Photo) source;
            PhotoTransformationState state = photo.save_transformation_state();
            state.broken.connect(on_state_broken);
            
            map.set(photo, state);
        }
    }
    
    ~MultiplePhotoTransformationCommand() {
        foreach (PhotoTransformationState state in map.values)
            state.broken.disconnect(on_state_broken);
    }
    
    public override void undo_on_source(DataSource source) {
        Photo photo = (Photo) source;
        
        PhotoTransformationState state = map.get(photo);
        assert(state != null);
        
        photo.load_transformation_state(state);
    }
    
    private void on_state_broken() {
        get_command_manager().reset();
    }
}

public class RotateSingleCommand : SingleDataSourceCommand {
    private Rotation rotation;
    
    public RotateSingleCommand(Photo photo, Rotation rotation, string name, string explanation) {
        base(photo, name, explanation);
        
        this.rotation = rotation;
    }
    
    public override void execute() {
        ((Photo) source).rotate(rotation);
    }
    
    public override void undo() {
        ((Photo) source).rotate(rotation.opposite());
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
        ((Photo) source).rotate(rotation);
    }
    
    public override void undo_on_source(DataSource source) {
        ((Photo) source).rotate(rotation.opposite());
    }
}

public class EditTitleCommand : SingleDataSourceCommand {
    private string new_title;
    private string? old_title;
    
    public EditTitleCommand(LibraryPhoto photo, string new_title) {
        base(photo, Resources.EDIT_TITLE_LABEL, Resources.EDIT_TITLE_TOOLTIP);
        
        this.new_title = new_title;
        old_title = photo.get_title();
    }
    
    public override void execute() {
        ((LibraryPhoto) source).set_title(new_title);
    }
    
    public override void undo() {
        ((LibraryPhoto) source).set_title(old_title);
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
    public RevertSingleCommand(Photo photo) {
        base(photo, Resources.REVERT_LABEL, Resources.REVERT_TOOLTIP);
    }
    
    public override void execute_on_photo(Photo photo) {
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
        base(iter, _("Reverting"), _("Undoing Revert"), Resources.REVERT_LABEL,
            Resources.REVERT_TOOLTIP);
    }
    
    public override void execute_on_source(DataSource source) {
        ((Photo) source).remove_all_transformations();
    }
}

public class EnhanceSingleCommand : GenericPhotoTransformationCommand {
    public EnhanceSingleCommand(Photo photo) {
        base(photo, Resources.ENHANCE_LABEL, Resources.ENHANCE_TOOLTIP);
    }
    
    public override void execute_on_photo(Photo photo) {
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
        base(iter, _("Enhancing"), _("Undoing Enhance"), Resources.ENHANCE_LABEL,
            Resources.ENHANCE_TOOLTIP);
    }
    
    public override void execute_on_source(DataSource source) {
        ((Photo) source).enhance();
    }
}

public class CropCommand : GenericPhotoTransformationCommand {
    private Box crop;
    
    public CropCommand(Photo photo, Box crop, string name, string explanation) {
        base(photo, name, explanation);
        
        this.crop = crop;
    }
    
    public override void execute_on_photo(Photo photo) {
        photo.set_crop(crop);
    }
}

public class AdjustColorsCommand : GenericPhotoTransformationCommand {
    private PixelTransformationBundle transformations;
    
    public AdjustColorsCommand(Photo photo, PixelTransformationBundle transformations,
        string name, string explanation) {
        base(photo, name, explanation);
        
        this.transformations = transformations;
    }
    
    public override void execute_on_photo(Photo photo) {
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
    
    public RedeyeCommand(Photo photo, RedeyeInstance redeye_instance, string name,
        string explanation) {
        base(photo, name, explanation);
        
        this.redeye_instance = redeye_instance;
    }
    
    public override void execute_on_photo(Photo photo) {
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
        
        public RealMovePhotosCommand(Event? new_event, Gee.Iterable<DataView> photos,
            string progress_text, string undo_progress_text, string name, string explanation) {
            base(photos, progress_text, undo_progress_text, name, explanation);
            
            // get proxies for the photos' events
            foreach (DataSource source in source_list) {
                LibraryPhoto photo = (LibraryPhoto) source;
                Event? old_event = photo.get_event();
                SourceProxy? old_event_proxy = (old_event != null) ? old_event.get_proxy() : null;
                
                // if any of the proxies break, the show's off
                if (old_event_proxy != null)
                    old_event_proxy.broken.connect(on_proxy_broken);
                
                old_photo_events.set(photo, old_event_proxy);
            }
            
            // stash the proxy of the new event
            new_event_proxy = new_event.get_proxy();
            new_event_proxy.broken.connect(on_proxy_broken);
        }
        
        ~RealMovePhotosCommand() {
            new_event_proxy.broken.disconnect(on_proxy_broken);
            
            foreach (SourceProxy? proxy in old_photo_events.values) {
                if (proxy != null)
                    proxy.broken.disconnect(on_proxy_broken);
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

        real_command = new RealMovePhotosCommand(new_event, iter, _("Creating New Event"),
            _("Removing Event"), Resources.NEW_EVENT_LABEL,
            Resources.NEW_EVENT_TOOLTIP);
    }
}

public class SetEventCommand : MovePhotosCommand {
    public SetEventCommand(Gee.Iterable<DataView> iter, Event new_event) {
        base(Resources.SET_PHOTO_EVENT_LABEL, Resources.SET_PHOTO_EVENT_TOOLTIP);

        real_command = new RealMovePhotosCommand(new_event, iter, _("Moving Photos to New Event"),
            _("Setting Photos to Previous Event"), Resources.SET_PHOTO_EVENT_LABEL, 
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
        
        real_command = new RealMovePhotosCommand(master_event, photos, _("Merging"), 
            _("Unmerging"), Resources.MERGE_LABEL, Resources.MERGE_TOOLTIP);
    }
}

public class DuplicateMultiplePhotosCommand : MultipleDataSourceCommand {
    private Gee.HashMap<LibraryPhoto, LibraryPhoto> dupes = new Gee.HashMap<LibraryPhoto, LibraryPhoto>();
    private int failed = 0;
    
    public DuplicateMultiplePhotosCommand(Gee.Iterable<DataView> iter) {
        base (iter, _("Duplicating photos"), _("Removing duplicated photos"), 
            Resources.DUPLICATE_PHOTO_LABEL, Resources.DUPLICATE_PHOTO_TOOLTIP);
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
    }
    
    ~DuplicateMultiplePhotosCommand() {
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
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
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
        
        base.undo();
        
        // be sure to drop everything that was destroyed
        dupes.clear();
        failed = 0;
        
        // re-monitor for duplicates' destruction
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
    }
    
    public override void undo_on_source(DataSource source) {
        LibraryPhoto photo = (LibraryPhoto) source;
        
        Marker marker = LibraryPhoto.global.mark(dupes.get(photo));
        LibraryPhoto.global.destroy_marked(marker, true);
    }
}

public class SetRatingSingleCommand : SingleDataSourceCommand {
    private Rating last_rating;
    private Rating new_rating;
    private bool set_direct;
    private bool incrementing;

    public SetRatingSingleCommand(DataSource source, Rating rating) {
        base (source, Resources.rating_label(rating), Resources.rating_tooltip(rating));
        set_direct = true;
        new_rating = rating;

        last_rating = ((LibraryPhoto)source).get_rating();
    }

    public SetRatingSingleCommand.inc_dec(DataSource source, bool is_incrementing) {
        base (source, is_incrementing ? Resources.INCREASE_RATING_LABEL : 
            Resources.DECREASE_RATING_LABEL, is_incrementing ? Resources.INCREASE_RATING_TOOLTIP :
            Resources.DECREASE_RATING_TOOLTIP);
        set_direct = false;
        incrementing = is_incrementing;

        last_rating = ((LibraryPhoto)source).get_rating();
    }

    public override void execute() {
        if (set_direct)
            ((LibraryPhoto) source).set_rating(new_rating);
        else {
            if (incrementing) 
                ((LibraryPhoto) source).increase_rating();
            else
                ((LibraryPhoto) source).decrease_rating();
        }
    }
    
    public override void undo() {
        ((LibraryPhoto) source).set_rating(last_rating);
    }
}

public class SetRatingCommand : MultipleDataSourceCommand {
    private Gee.HashMap<DataSource, Rating> last_rating_map;
    private Rating new_rating;
    private bool set_direct;
    private bool incrementing;
    private int action_count = 0;

    public SetRatingCommand(Gee.Iterable<DataView> iter, Rating rating) {
        base (iter, Resources.rating_progress(rating), _("Restoring previous rating"),
            Resources.rating_label(rating), Resources.rating_tooltip(rating));
        set_direct = true;
        new_rating = rating;

        save_source_states(iter);
    } 
    
    public SetRatingCommand.inc_dec(Gee.Iterable<DataView> iter, bool is_incrementing) {
        base (iter, 
            is_incrementing ? _("Increasing ratings") : _("Decreasing ratings"),
            is_incrementing ? _("Decreasing ratings") : _("Increasing ratings"), 
            is_incrementing ? Resources.INCREASE_RATING_LABEL : Resources.DECREASE_RATING_LABEL, 
            is_incrementing ? Resources.INCREASE_RATING_TOOLTIP : Resources.DECREASE_RATING_TOOLTIP);
        set_direct = false;
        incrementing = is_incrementing;
        
        save_source_states(iter);
    }
    
    private void save_source_states(Gee.Iterable<DataView> iter) {
        last_rating_map = new Gee.HashMap<DataSource, Rating>();

        foreach (DataView view in iter) {
            DataSource source = view.get_source();
            last_rating_map[source] = ((LibraryPhoto)source).get_rating();
        }
    }
    
    public override void execute() {
        action_count = 0;
        LibraryPhoto.global.freeze_notifications();
        base.execute();
        LibraryPhoto.global.thaw_notifications();
    }
    
    public override void undo() {
        action_count = 0;
        LibraryPhoto.global.freeze_notifications();
        base.undo();
        LibraryPhoto.global.thaw_notifications();
    }
    
    public override void execute_on_source(DataSource source) {
        if (set_direct)
            ((LibraryPhoto) source).set_rating(new_rating);
        else {
            if (incrementing)
                ((LibraryPhoto) source).increase_rating();
            else
                ((LibraryPhoto) source).decrease_rating();
        }
        
        // TODO: Replace this system with a mass set rating function (like Photo.set_event_many)
        if (++action_count % 50 == 0) {
            LibraryPhoto.global.thaw_notifications();
            LibraryPhoto.global.freeze_notifications();
        }
    }
    
    public override void undo_on_source(DataSource source) {
        ((LibraryPhoto) source).set_rating(last_rating_map[source]);
        
        if (++action_count % 50 == 0) {
            LibraryPhoto.global.thaw_notifications();
            LibraryPhoto.global.freeze_notifications();
        }
    }
}

public class AdjustDateTimePhotoCommand : SingleDataSourceCommand {
    private Photo photo;
    private int64 time_shift;
    private bool modify_original;

    public AdjustDateTimePhotoCommand(Photo photo, int64 time_shift, bool modify_original) {
        base(photo, Resources.ADJUST_DATE_TIME_LABEL, Resources.ADJUST_DATE_TIME_TOOLTIP);

        this.photo = photo;
        this.time_shift = time_shift;
        this.modify_original = modify_original;
    }

    public override void execute() {
        set_time(photo, photo.get_exposure_time() + (time_t) time_shift);
    }

    public override void undo() {
        set_time(photo, photo.get_exposure_time() - (time_t) time_shift);
    }

    private void set_time(Photo photo, time_t exposure_time) {
        if (modify_original) {
            try {
                photo.set_exposure_time_persistent(exposure_time);
            } catch(GLib.Error err) {
                AppWindow.error_message(_("Original photo could not be adjusted."));
            }
        } else {
            photo.set_exposure_time(exposure_time);
        }
    }
}

public class AdjustDateTimePhotosCommand : MultipleDataSourceCommand {
    private int64 time_shift;
    private bool keep_relativity;
    private bool modify_originals;

    // used when photos are batch changed instead of shifted uniformly
    private time_t? new_time = null;
    private Gee.HashMap<Photo, time_t?> old_times;
    private Gee.ArrayList<Photo> error_list;

    public AdjustDateTimePhotosCommand(Gee.Iterable<DataView> iter, int64 time_shift,
        bool keep_relativity, bool modify_originals) {
        base(iter, _("Adjusting Date and Time"), _("Undoing Date and Time Adjustment"),
            Resources.ADJUST_DATE_TIME_LABEL, Resources.ADJUST_DATE_TIME_TOOLTIP);

        this.time_shift = time_shift;
        this.keep_relativity = keep_relativity;
        this.modify_originals = modify_originals;

        // TODO: implement modify originals option

        // this should be replaced by a first function when we migrate to Gee's List
        foreach (DataView view in iter) { 
           if (new_time == null) {
                new_time = ((PhotoSource) view.get_source()).get_exposure_time() +
                    (time_t) time_shift;
                break;
            }            
        }

        old_times = new Gee.HashMap<Photo, time_t?>();
    }

    public override void execute() {
        error_list = new Gee.ArrayList<Photo>();
        base.execute();

        if (error_list.size > 0) {
            multiple_object_error_dialog(error_list, 
                ngettext("One original photo could not be adjusted.",
                "The following original photos could not be adjusted.", error_list.size), 
                _("Time Adjustment Error"));
        }
    }

    public override void undo() {
        error_list = new Gee.ArrayList<Photo>();
        base.undo();

        if (error_list.size > 0) {
            multiple_object_error_dialog(error_list, 
                ngettext("Time adjustments could not be undone on the following photo file.",
                "Time adjustments could not be undone on the following photo files.", 
                error_list.size), _("Time Adjustment Error"));
        }
    }

    private void set_time(Photo photo, time_t exposure_time) {
        if (modify_originals) {
            try {
                photo.set_exposure_time_persistent(exposure_time);
            } catch(GLib.Error err) {
                error_list.add(photo);
            }
        } else {
            photo.set_exposure_time(exposure_time);
        }
    }

    public override void execute_on_source(DataSource source) {
        Photo photo = ((Photo) source);

        if (keep_relativity && photo.get_exposure_time() != 0) {
            set_time(photo, photo.get_exposure_time() + (time_t) time_shift);
        } else {
            old_times.set(photo, photo.get_exposure_time());
            set_time(photo, new_time);
        }
    }

    public override void undo_on_source(DataSource source) {
        Photo photo = ((Photo) source);

        if (old_times.has_key(photo)) {
            set_time(photo, old_times.get(photo));
            old_times.unset(photo);
        } else {
            set_time(photo, photo.get_exposure_time() - (time_t) time_shift);
        }
    }
}

public class AddTagsCommand : PageCommand {
    private Gee.HashMap<SourceProxy, Gee.ArrayList<LibraryPhoto>> map =
        new Gee.HashMap<SourceProxy, Gee.ArrayList<LibraryPhoto>>();
    
    public AddTagsCommand(string[] names, Gee.Collection<LibraryPhoto> photos) {
        base (Resources.add_tags_label(names), Resources.ADD_TAGS_TOOLTIP);
        
        // load/create the tags here rather than in execute() so that we can merely use the proxy
        // to access it ... this is important with the redo() case, where the tags may have been
        // created by another proxy elsewhere
        foreach (string name in names) {
            Tag tag = Tag.for_name(name);
            SourceProxy tag_proxy = tag.get_proxy();
            
            // for each Tag, only attach photos which are not already attached, otherwise undo()
            // will not be symmetric
            Gee.ArrayList<LibraryPhoto> add_photos = new Gee.ArrayList<LibraryPhoto>();
            foreach (LibraryPhoto photo in photos) {
                if (!tag.contains(photo))
                    add_photos.add(photo);
            }
            
            if (add_photos.size > 0) {
                tag_proxy.broken.connect(on_proxy_broken);
                map.set(tag_proxy, add_photos);
            }
        }
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
    }
    
    ~AddTagsCommand() {
        foreach (SourceProxy tag_proxy in map.keys)
            tag_proxy.broken.disconnect(on_proxy_broken);
        
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
    }
    
    public override void execute() {
        foreach (SourceProxy tag_proxy in map.keys)
            ((Tag) tag_proxy.get_source()).attach_many(map.get(tag_proxy));
    }
    
    public override void undo() {
        foreach (SourceProxy tag_proxy in map.keys)
            ((Tag) tag_proxy.get_source()).detach_many(map.get(tag_proxy));
    }
    
    private void on_photo_destroyed(DataSource source) {
        foreach (Gee.ArrayList<LibraryPhoto> photos in map.values) {
            if (photos.contains((LibraryPhoto) source)) {
                get_command_manager().reset();
                
                return;
            }
        }
    }
    
    private void on_proxy_broken() {
        get_command_manager().reset();
    }
}

public class RenameTagCommand : SimpleProxyableCommand {
    private string old_name;
    private string new_name;
    
    public RenameTagCommand(Tag tag, string new_name) {
        base (tag, Resources.rename_tag_label(tag.get_name(), new_name), 
            Resources.rename_tag_tooltip(tag.get_name()));
        
        old_name = tag.get_name();
        this.new_name = new_name;
    }
    
    protected override void execute_on_source(DataSource source) {
        if (!((Tag) source).rename(new_name))
            AppWindow.error_message(Resources.rename_tag_exists_message(new_name));
    }

    protected override void undo_on_source(DataSource source) {
        if (!((Tag) source).rename(old_name))
            AppWindow.error_message(Resources.rename_tag_exists_message(old_name));
    }
}

public class DeleteTagCommand : SimpleProxyableCommand {
    public DeleteTagCommand(Tag tag) {
        base (tag, Resources.delete_tag_label(tag.get_name()),
            Resources.delete_tag_tooltip(tag.get_name(), tag.get_photos_count()));
    }
    
    protected override void execute_on_source(DataSource source) {
        Tag.global.destroy_marked(Tag.global.mark(source), false);
    }
    
    protected override void undo_on_source(DataSource source) {
        // merely instantiating the Tag will rehydrate it ... should always work, because the 
        // undo stack is cleared if the proxy ever breaks
        assert(source is Tag);
    }
}

public class ModifyTagsCommand : SingleDataSourceCommand {
    private LibraryPhoto photo;
    private Gee.ArrayList<SourceProxy> to_add = new Gee.ArrayList<SourceProxy>();
    private Gee.ArrayList<SourceProxy> to_remove = new Gee.ArrayList<SourceProxy>();
    
    public ModifyTagsCommand(LibraryPhoto photo, Gee.Collection<Tag> new_tag_list) {
        base (photo, Resources.MODIFY_TAGS_LABEL, Resources.MODIFY_TAGS_TOOLTIP);
        
        this.photo = photo;
        
        // Remove any tag that's in the original list but not the new one
        Gee.List<Tag>? original_tags = Tag.global.fetch_for_photo(photo);
        if (original_tags != null) {
		    foreach (Tag tag in original_tags) {
		        if (!new_tag_list.contains(tag)) {
		            SourceProxy proxy = tag.get_proxy();
		            
		            to_remove.add(proxy);
		            proxy.broken.connect(on_proxy_broken);
		        }
		    }
        }
        
        // Add any tag that's in the new list but not the original
        foreach (Tag tag in new_tag_list) {
            if (original_tags == null || !original_tags.contains(tag)) {
                SourceProxy proxy = tag.get_proxy();
                
                to_add.add(proxy);
                proxy.broken.connect(on_proxy_broken);
            }
        }
    }
    
    ~ModifyTagsCommand() {
        foreach (SourceProxy proxy in to_add)
            proxy.broken.disconnect(on_proxy_broken);
        
        foreach (SourceProxy proxy in to_remove)
            proxy.broken.disconnect(on_proxy_broken);
    }
    
    public override void execute() {
        foreach (SourceProxy proxy in to_add)
            ((Tag) proxy.get_source()).attach(photo);
        
        foreach (SourceProxy proxy in to_remove)
            ((Tag) proxy.get_source()).detach(photo);
    }
    
    public override void undo() {
        foreach (SourceProxy proxy in to_add)
            ((Tag) proxy.get_source()).detach(photo);
        
        foreach (SourceProxy proxy in to_remove)
            ((Tag) proxy.get_source()).attach(photo);
    }
    
    private void on_proxy_broken() {
        get_command_manager().reset();
    }
}

public class TagUntagPhotosCommand : SimpleProxyableCommand {
    private Gee.Collection<LibraryPhoto> photos;
    private bool attach;
    
    public TagUntagPhotosCommand(Tag tag, Gee.Collection<LibraryPhoto> photos, int count, bool attach) {
        base (tag,
            attach ? Resources.tag_photos_label(tag.get_name(), count) 
                : Resources.untag_photos_label(tag.get_name(), count),
            attach ? Resources.tag_photos_tooltip(tag.get_name(), count) 
                : Resources.untag_photos_tooltip(tag.get_name(), count));
        
        this.photos = photos;
        this.attach = attach;
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
    }
    
    ~TagPhotosCommand() {
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
    }
    
    public override void execute_on_source(DataSource source) {
        if (attach)
            ((Tag) source).attach_many(photos);
        else
            ((Tag) source).detach_many(photos);
    }
    
    public override void undo_on_source(DataSource source) {
        if (attach)
            ((Tag) source).detach_many(photos);
        else
            ((Tag) source).attach_many(photos);
    }
    
    private void on_photo_destroyed(DataSource source) {
        if (photos.contains((LibraryPhoto) source))
            get_command_manager().reset();
    }
}

public class TrashUntrashPhotosCommand : PageCommand {
    private Gee.Collection<LibraryPhoto> photos;
    private bool to_trash;
    
    public TrashUntrashPhotosCommand(Gee.Collection<LibraryPhoto> photos, bool to_trash) {
        base (
            to_trash ? _("Move Photos to Trash") : _("Restore Photos from Trash"),
            to_trash ? _("Move the photos to the Shotwell trash") : _("Restore the photos back to the Shotwell library"));
        
        this.photos = photos;
        this.to_trash = to_trash;
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
    }
    
    ~TrashUntrashPhotosCommand() {
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
    }
    
    private ProgressDialog? get_progress_dialog(bool to_trash) {
        if (photos.size <= 5)
            return null;
        
        ProgressDialog dialog = new ProgressDialog(AppWindow.get_instance(),
            to_trash ? _("Moving Photos to Trash") : _("Restoring Photos From Trash"));
        dialog.update_display_every((photos.size / 5).clamp(2, 10));
        
        return dialog;
    }
    
    public override void execute() {
        ProgressDialog? dialog = get_progress_dialog(to_trash);
        
        ProgressMonitor monitor = null;
        if (dialog != null)
            monitor = dialog.monitor;
        
        if (to_trash)
            trash(monitor);
        else
            untrash(monitor);
        
        if (dialog != null)
            dialog.close();
    }
    
    public override void undo() {
        ProgressDialog? dialog = get_progress_dialog(!to_trash);
        
        ProgressMonitor monitor = null;
        if (dialog != null)
            monitor = dialog.monitor;
        
        if (to_trash)
            untrash(monitor);
        else
            trash(monitor);
        
        if (dialog != null)
            dialog.close();
    }
    
    private void trash(ProgressMonitor? monitor) {
        int ctr = 0;
        int count = photos.size;
        LibraryPhoto.global.freeze_notifications();
        foreach (LibraryPhoto photo in photos) {
            photo.trash();
            if (monitor != null)
                monitor(++ctr, count);
            
            if (ctr % 100 == 0) {
                LibraryPhoto.global.thaw_notifications();
                LibraryPhoto.global.freeze_notifications();
            }
        }
        LibraryPhoto.global.thaw_notifications();
    }
    
    private void untrash(ProgressMonitor? monitor) {
        int ctr = 0;
        int count = photos.size;
        LibraryPhoto.global.freeze_notifications();
        foreach (LibraryPhoto photo in photos) {
            photo.untrash();
            if (monitor != null)
                monitor(++ctr, count);
            
            if (ctr % 100 == 0) {
                LibraryPhoto.global.thaw_notifications();
                LibraryPhoto.global.freeze_notifications();
            }
        }
        LibraryPhoto.global.thaw_notifications();
    }
    
    private void on_photo_destroyed(DataSource source) {
        // in this case, don't need to reset the command manager, simply remove the photo from the
        // internal list and allow the others to be moved to and from the trash
        photos.remove((LibraryPhoto) source);
        
        // however, if all photos missing, then remove this from the command stack, and there's
        // only one way to do that
        if (photos.size == 0)
            get_command_manager().reset();
    }
}

