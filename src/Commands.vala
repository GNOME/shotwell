/* Copyright 2016 Software Freedom Conservancy Inc.
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
    
    protected PageCommand(string name, string explanation) {
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
                    if ( ((Thumbnail) collection_page.get_view().get_at(i)).get_media_source() == library_photo) {
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
    
    protected SingleDataSourceCommand(DataSource source, string name, string explanation) {
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
    private Gee.HashSet<SourceProxy> proxies = new Gee.HashSet<SourceProxy>();
    
    protected SimpleProxyableCommand(Proxyable proxyable, string name, string explanation) {
        base (name, explanation);
        
        proxy = proxyable.get_proxy();
        proxy.broken.connect(on_proxy_broken);
    }
    
    ~SimpleProxyableCommand() {
        proxy.broken.disconnect(on_proxy_broken);
        clear_added_proxies();
    }
    
    public override void execute() {
        execute_on_source(proxy.get_source());
    }
    
    protected abstract void execute_on_source(DataSource source);
    
    public override void undo() {
        undo_on_source(proxy.get_source());
    }
    
    protected abstract void undo_on_source(DataSource source);
    
    // If the Command deals with other Proxyables during processing, it can add them here and the
    // SimpleProxyableCommand will deal with created a SourceProxy and if it signals it's broken.
    // Note that these cannot be removed programatically, but only cleared en masse; it's expected
    // this is fine for the nature of a Command.
    protected void add_proxyables(Gee.Collection<Proxyable> proxyables) {
        foreach (Proxyable proxyable in proxyables) {
            SourceProxy added_proxy = proxyable.get_proxy();
            added_proxy.broken.connect(on_proxy_broken);
            proxies.add(added_proxy);
        }
    }
    
    // See add_proxyables() for a note on use.
    protected void clear_added_proxies() {
        foreach (SourceProxy added_proxy in proxies)
            added_proxy.broken.disconnect(on_proxy_broken);
        
        proxies.clear();
    }
    
    private void on_proxy_broken() {
        debug("on_proxy_broken");
        get_command_manager().reset();
    }
}

public abstract class SinglePhotoTransformationCommand : SingleDataSourceCommand {
    private PhotoTransformationState state;
    
    protected SinglePhotoTransformationCommand(Photo photo, string name, string explanation) {
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
    
    protected GenericPhotoTransformationCommand(Photo photo, string name, string explanation) {
        base(photo, name, explanation);
    }
    
    ~GenericPhotoTransformationCommand() {
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
    private Gee.ArrayList<DataSource> acted_upon = new Gee.ArrayList<DataSource>();
    private Gee.HashSet<SourceCollection> hooked_collections = new Gee.HashSet<SourceCollection>();
    
    protected MultipleDataSourceCommand(Gee.Iterable<DataView> iter, string progress_text,
        string undo_progress_text, string name, string explanation) {
        base(name, explanation);
        
        this.progress_text = progress_text;
        this.undo_progress_text = undo_progress_text;
        
        foreach (DataView view in iter) {
            DataSource source = view.get_source();
            SourceCollection? collection = (SourceCollection) source.get_membership();
    
            if (collection != null) {
                hooked_collections.add(collection);
            }
            source_list.add(source);
        }
        
        foreach (SourceCollection current_collection in hooked_collections) {
            current_collection.item_destroyed.connect(on_source_destroyed);
        }
    }
    
    ~MultipleDataSourceCommand() {
        foreach (SourceCollection current_collection in hooked_collections) {
            current_collection.item_destroyed.disconnect(on_source_destroyed);
        }
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
        
        start_transaction();
        execute_all(true, true, source_list, acted_upon);
        commit_transaction();
    }
    
    public abstract void execute_on_source(DataSource source);
    
    public override void undo() {
        if (acted_upon.size > 0) {
            start_transaction();
            execute_all(false, false, acted_upon, null);
            commit_transaction();
            
            acted_upon.clear();
        }
    }
    
    public abstract void undo_on_source(DataSource source);
    
    private void start_transaction() {
        foreach (SourceCollection sources in hooked_collections) {
            MediaSourceCollection? media_collection = sources as MediaSourceCollection;
            if (media_collection != null)
                media_collection.transaction_controller.begin();
        }
    }
    
    private void commit_transaction() {
        foreach (SourceCollection sources in hooked_collections) {
            MediaSourceCollection? media_collection = sources as MediaSourceCollection;
            if (media_collection != null)
                media_collection.transaction_controller.commit();
        }
    }
    
    private void execute_all(bool exec, bool can_cancel, Gee.ArrayList<DataSource> todo, 
        Gee.ArrayList<DataSource>? completed) {
        AppWindow.get_instance().set_busy_cursor();
        
        int count = 0;
        int total = todo.size;
        int two_percent = (int) ((double) total / 50.0);
        if (two_percent <= 0)
            two_percent = 1;
        
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
                if ((++count % two_percent) == 0) {
                    progress.set_fraction(count, total);
                    spin_event_loop();
                }
                
                if (cancellable != null && cancellable.is_cancelled())
                    break;
            }
        }
        
        if (progress != null)
            progress.close();
        
        AppWindow.get_instance().set_normal_cursor();
    }
}

// TODO: Upgrade MultipleDataSourceAtOnceCommand to use TransactionControllers.
public abstract class MultipleDataSourceAtOnceCommand : PageCommand {
    private Gee.HashSet<DataSource> sources = new Gee.HashSet<DataSource>();
    private Gee.HashSet<SourceCollection> hooked_collections = new Gee.HashSet<SourceCollection>();
    
    protected MultipleDataSourceAtOnceCommand(Gee.Collection<DataSource> sources, string name,
        string explanation) {
        base (name, explanation);
        
        this.sources.add_all(sources);
        
        foreach (DataSource source in this.sources) {
            SourceCollection? membership = source.get_membership() as SourceCollection;
            if (membership != null)
                hooked_collections.add(membership);
        }
        
        foreach (SourceCollection source_collection in hooked_collections)
            source_collection.items_destroyed.connect(on_sources_destroyed);
    }
    
    ~MultipleDataSourceAtOnceCommand() {
        foreach (SourceCollection source_collection in hooked_collections)
            source_collection.items_destroyed.disconnect(on_sources_destroyed);
    }
    
    public override void execute() {
        AppWindow.get_instance().set_busy_cursor();
        
        DatabaseTable.begin_transaction();
        MediaCollectionRegistry.get_instance().freeze_all();
        
        execute_on_all(sources);
        
        MediaCollectionRegistry.get_instance().thaw_all();
        try {
            DatabaseTable.commit_transaction();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        } finally {
            AppWindow.get_instance().set_normal_cursor();
        }
    }
    
    protected abstract void execute_on_all(Gee.Collection<DataSource> sources);
    
    public override void undo() {
        AppWindow.get_instance().set_busy_cursor();
        
        DatabaseTable.begin_transaction();
        MediaCollectionRegistry.get_instance().freeze_all();
        
        undo_on_all(sources);
        
        MediaCollectionRegistry.get_instance().thaw_all();
        try {
            DatabaseTable.commit_transaction();
        } catch (DatabaseError err) {
            AppWindow.database_error(err);
        } finally {
            AppWindow.get_instance().set_normal_cursor();
        }
    }
    
    protected abstract void undo_on_all(Gee.Collection<DataSource> sources);
    
    private void on_sources_destroyed(Gee.Collection<DataSource> destroyed) {
        foreach (DataSource source in destroyed) {
            if (sources.contains(source)) {
                get_command_manager().reset();
                
                break;
            }
        }
    }
}

public abstract class MultiplePhotoTransformationCommand : MultipleDataSourceCommand {
    private Gee.HashMap<Photo, PhotoTransformationState> map = new Gee.HashMap<
        Photo, PhotoTransformationState>();
    
    protected MultiplePhotoTransformationCommand(Gee.Iterable<DataView> iter, string progress_text,
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
    
    public EditTitleCommand(MediaSource source, string new_title) {
        var title = GLib.dpgettext2 (null, "Button Label",
                Resources.EDIT_TITLE_LABEL);
        base(source, title, "");
        
        this.new_title = new_title;
        old_title = source.get_title();
    }
    
    public override void execute() {
        ((MediaSource) source).set_title(new_title);
    }
    
    public override void undo() {
        ((MediaSource) source).set_title(old_title);
    }
}

public class EditCommentCommand : SingleDataSourceCommand {
    private string new_comment;
    private string? old_comment;
    
    public EditCommentCommand(MediaSource source, string new_comment) {
        base(source, Resources.EDIT_COMMENT_LABEL, "");
        
        this.new_comment = new_comment;
        old_comment = source.get_comment();
    }
    
    public override void execute() {
        ((MediaSource) source).set_comment(new_comment);
    }
    
    public override void undo() {
        ((MediaSource) source).set_comment(old_comment);
    }
}

public class EditMultipleTitlesCommand : MultipleDataSourceAtOnceCommand {
    public string new_title;
    public Gee.HashMap<MediaSource, string?> old_titles = new Gee.HashMap<MediaSource, string?>();
    
    public EditMultipleTitlesCommand(Gee.Collection<MediaSource> media_sources, string new_title) {
        var title = GLib.dpgettext2 (null, "Button Label",
                Resources.EDIT_TITLE_LABEL);
        base (media_sources, title, "");
        
        this.new_title = new_title;
        foreach (MediaSource media in media_sources)
            old_titles.set(media, media.get_title());
    }
    
    public override void execute_on_all(Gee.Collection<DataSource> sources) {
        foreach (DataSource source in sources)
            ((MediaSource) source).set_title(new_title);
    }
    
    public override void undo_on_all(Gee.Collection<DataSource> sources) {
        foreach (DataSource source in sources)
            ((MediaSource) source).set_title(old_titles.get((MediaSource) source));
    }
}

public class EditMultipleCommentsCommand : MultipleDataSourceAtOnceCommand {
    public string new_comment;
    public Gee.HashMap<MediaSource, string?> old_comments = new Gee.HashMap<MediaSource, string?>();
    
    public EditMultipleCommentsCommand(Gee.Collection<MediaSource> media_sources, string new_comment) {
        base (media_sources, Resources.EDIT_COMMENT_LABEL, "");
        
        this.new_comment = new_comment;
        foreach (MediaSource media in media_sources)
            old_comments.set(media, media.get_comment());
    }
    
    public override void execute_on_all(Gee.Collection<DataSource> sources) {
        foreach (DataSource source in sources)
            ((MediaSource) source).set_comment(new_comment);
    }
    
    public override void undo_on_all(Gee.Collection<DataSource> sources) {
        foreach (DataSource source in sources)
            ((MediaSource) source).set_comment(old_comments.get((MediaSource) source));
    }
}

public class RenameEventCommand : SimpleProxyableCommand {
    private string new_name;
    private string? old_name;
    
    public RenameEventCommand(Event event, string new_name) {
        base(event, Resources.RENAME_EVENT_LABEL, "");
        
        this.new_name = new_name;
        old_name = event.get_raw_name();
    }
    
    public override void execute_on_source(DataSource source) {
        ((Event) source).rename(new_name);
    }
    
    public override void undo_on_source(DataSource source) {
        ((Event) source).rename(old_name);
    }
}

public class EditEventCommentCommand : SimpleProxyableCommand {
    private string new_comment;
    private string? old_comment;
    
    public EditEventCommentCommand(Event event, string new_comment) {
        base(event, Resources.EDIT_COMMENT_LABEL, "");
        
        this.new_comment = new_comment;
        old_comment = event.get_comment();
    }
    
    public override void execute_on_source(DataSource source) {
        ((Event) source).set_comment(new_comment);
    }
    
    public override void undo_on_source(DataSource source) {
        ((Event) source).set_comment(old_comment);
    }
}

public class SetKeyPhotoCommand : SingleDataSourceCommand {
    private MediaSource new_primary_source;
    private MediaSource old_primary_source;
    
    public SetKeyPhotoCommand(Event event, MediaSource new_primary_source) {
        base(event, Resources.MAKE_KEY_PHOTO_LABEL, "");
        
        this.new_primary_source = new_primary_source;
        old_primary_source = event.get_primary_source();
    }
    
    public override void execute() {
        ((Event) source).set_primary_source(new_primary_source);
    }
    
    public override void undo() {
        ((Event) source).set_primary_source(old_primary_source);
    }
}

public class RevertSingleCommand : GenericPhotoTransformationCommand {
    public RevertSingleCommand(Photo photo) {
        base(photo, Resources.REVERT_LABEL, "");
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
            "");
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

public class StraightenCommand : GenericPhotoTransformationCommand {
    private double theta;
    private Box crop;   // straightening can change the crop rectangle
    
    public StraightenCommand(Photo photo, double theta, Box crop, string name, string explanation) {
        base(photo, name, explanation);
        
        this.theta = theta;
        this.crop = crop;
    }
    
    public override void execute_on_photo(Photo photo) {
        // thaw collection so both alterations are signalled at the same time
        DataCollection? collection = photo.get_membership();
        if (collection != null)
            collection.freeze_notifications();
        
        photo.set_straighten(theta);
        photo.set_crop(crop);
        
        if (collection != null)
            collection.thaw_notifications();
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

public class AdjustColorsSingleCommand : GenericPhotoTransformationCommand {
    private PixelTransformationBundle transformations;
    
    public AdjustColorsSingleCommand(Photo photo, PixelTransformationBundle transformations,
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
        return command is AdjustColorsSingleCommand;
    }
}

public class AdjustColorsMultipleCommand : MultiplePhotoTransformationCommand {
    private PixelTransformationBundle transformations;
    
    public AdjustColorsMultipleCommand(Gee.Iterable<DataView> iter,
        PixelTransformationBundle transformations, string name, string explanation) {
        base(iter, _("Applying Color Transformations"), _("Undoing Color Transformations"),
            name, explanation);
        
        this.transformations = transformations;
    }
    
    public override void execute_on_source(DataSource source) {
        ((Photo) source).set_color_adjustments(transformations);
    }
}

public class RedeyeCommand : GenericPhotoTransformationCommand {
    private EditingTools.RedeyeInstance redeye_instance;
    
    public RedeyeCommand(Photo photo, EditingTools.RedeyeInstance redeye_instance, string name,
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
    // construction, if needed
    protected class RealMovePhotosCommand : MultipleDataSourceCommand {
        private SourceProxy new_event_proxy = null;
        private Gee.HashMap<MediaSource, SourceProxy?> old_events = new Gee.HashMap<
            MediaSource, SourceProxy?>();
        
        public RealMovePhotosCommand(Event? new_event, Gee.Iterable<DataView> source_views,
            string progress_text, string undo_progress_text, string name, string explanation) {
            base(source_views, progress_text, undo_progress_text, name, explanation);
            
            // get proxies for each media source's event
            foreach (DataSource source in source_list) {
                MediaSource current_media = (MediaSource) source;
                Event? old_event = current_media.get_event();
                SourceProxy? old_event_proxy = (old_event != null) ? old_event.get_proxy() : null;
                
                // if any of the proxies break, the show's off
                if (old_event_proxy != null)
                    old_event_proxy.broken.connect(on_proxy_broken);
                
                old_events.set(current_media, old_event_proxy);
            }
            
            // stash the proxy of the new event
            new_event_proxy = new_event.get_proxy();
            new_event_proxy.broken.connect(on_proxy_broken);
        }
        
        ~RealMovePhotosCommand() {
            new_event_proxy.broken.disconnect(on_proxy_broken);
            
            foreach (SourceProxy? proxy in old_events.values) {
                if (proxy != null)
                    proxy.broken.disconnect(on_proxy_broken);
            }
        }
        
        public override void execute() {
            // create the new event
            base.execute();

            // Are we at an event page already?
            if ((LibraryWindow.get_app().get_current_page() is EventPage)) {
                Event evt = ((EventPage) LibraryWindow.get_app().get_current_page()).get_event();
                
                // Will moving these empty this event?
                if (evt.get_media_count() == source_list.size) {
                    // Yes - jump away from this event, since it will have zero
                    // entries and is going to be removed.
                    LibraryWindow.get_app().switch_to_event((Event) new_event_proxy.get_source());
                }
            } else {
                // We're in a library or tag page.
                
                // Are we moving these to a newly-created event (i.e. has same size)?
                if (((Event) new_event_proxy.get_source()).get_media_count() == source_list.size) {
                    // Yes - jump to the new event.
                    LibraryWindow.get_app().switch_to_event((Event) new_event_proxy.get_source());
                }
            }
            // Otherwise - don't jump; users found the jumping disconcerting.
        }
        
        public override void execute_on_source(DataSource source) {
            ((MediaSource) source).set_event((Event?) new_event_proxy.get_source());
        }
        
        public override void undo_on_source(DataSource source) {
            MediaSource current_media = (MediaSource) source;
            SourceProxy? event_proxy = old_events.get(current_media);
            
            current_media.set_event(event_proxy != null ? (Event?) event_proxy.get_source() : null);
        }
        
        private void on_proxy_broken() {
            get_command_manager().reset();
        }
    }

    protected RealMovePhotosCommand real_command;
    
    protected MovePhotosCommand(string name, string explanation) {
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
        base(Resources.NEW_EVENT_LABEL, "");

        // get the primary or "key" source for the new event (which is simply the first one)
        MediaSource key_source = null;
        foreach (DataView view in iter) {
            MediaSource current_source = (MediaSource) view.get_source();
            
            if (key_source == null) {
                key_source = current_source;
                break;
            }
        }
        
        // key photo is required for an event
        assert(key_source != null);

        Event new_event = Event.create_empty_event(key_source);

        real_command = new RealMovePhotosCommand(new_event, iter, _("Creating New Event"),
            _("Removing Event"), Resources.NEW_EVENT_LABEL,
            "");
    }
}

public class SetEventCommand : MovePhotosCommand {
    public SetEventCommand(Gee.Iterable<DataView> iter, Event new_event) {
        base(Resources.SET_PHOTO_EVENT_LABEL, Resources.SET_PHOTO_EVENT_TOOLTIP);

        real_command = new RealMovePhotosCommand(new_event, iter, _("Moving Photos to New Event"),
            _("Setting Photos to Previous Event"), Resources.SET_PHOTO_EVENT_LABEL, 
            "");
    }
}

public class MergeEventsCommand : MovePhotosCommand {
    public MergeEventsCommand(Gee.Iterable<DataView> iter) {
        base (Resources.MERGE_LABEL, "");
        
        // Because it requires fewer operations to merge small events onto large ones,
        // rather than the other way round, we try to choose the event with the most
        // sources as the 'master', preferring named events over unnamed ones so that
        // names can persist.
        Event master_event = null;
        int named_evt_src_count = 0;
        int unnamed_evt_src_count = 0;
        Gee.ArrayList<ThumbnailView> media_thumbs = new Gee.ArrayList<ThumbnailView>();
        
        foreach (DataView view in iter) {
            Event event = (Event) view.get_source();
            
            // First event we've examined?
            if (master_event == null) {
                // Yes. Make it the master for now and remember it as
                // having the most sources (out of what we've seen so far).
                master_event = event;
                unnamed_evt_src_count = master_event.get_media_count();
                if (event.has_name())
                    named_evt_src_count = master_event.get_media_count();
            } else {
                // No. Check whether this event has a name and whether
                // it has more sources than any other we've seen...
                if (event.has_name()) {
                    if (event.get_media_count() > named_evt_src_count) {
                        named_evt_src_count = event.get_media_count();
                        master_event = event;
                    }
                } else if (named_evt_src_count == 0) {
                    // Per the original app design, named events -always- trump
                    // unnamed ones, so only choose an unnamed one if we haven't
                    // seen any named ones yet.
                    if (event.get_media_count() > unnamed_evt_src_count) {
                        unnamed_evt_src_count = event.get_media_count();
                        master_event = event;
                    }
                }
            }
            
            // store all media sources in this operation; they will be moved to the master event
            // (keep proxies of their original event for undo)
            foreach (MediaSource media_source in event.get_media())
                media_thumbs.add(new ThumbnailView(media_source));
        }
        
        assert(master_event != null);
        assert(media_thumbs.size > 0);
        
        real_command = new RealMovePhotosCommand(master_event, media_thumbs, _("Merging"), 
            _("Unmerging"), Resources.MERGE_LABEL, "");
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
        base (source, Resources.rating_label(rating), "");
        set_direct = true;
        new_rating = rating;

        last_rating = ((LibraryPhoto)source).get_rating();
    }

    public SetRatingSingleCommand.inc_dec(DataSource source, bool is_incrementing) {
        base (source, is_incrementing ? Resources.INCREASE_RATING_LABEL : 
            Resources.DECREASE_RATING_LABEL, "");
        set_direct = false;
        incrementing = is_incrementing;

        last_rating = ((MediaSource) source).get_rating();
    }

    public override void execute() {
        if (set_direct)
            ((MediaSource) source).set_rating(new_rating);
        else {
            if (incrementing) 
                ((MediaSource) source).increase_rating();
            else
                ((MediaSource) source).decrease_rating();
        }
    }
    
    public override void undo() {
        ((MediaSource) source).set_rating(last_rating);
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
            Resources.rating_label(rating), "");
        set_direct = true;
        new_rating = rating;

        save_source_states(iter);
    } 
    
    public SetRatingCommand.inc_dec(Gee.Iterable<DataView> iter, bool is_incrementing) {
        base (iter, 
            is_incrementing ? _("Increasing ratings") : _("Decreasing ratings"),
            is_incrementing ? _("Decreasing ratings") : _("Increasing ratings"), 
            is_incrementing ? Resources.INCREASE_RATING_LABEL : Resources.DECREASE_RATING_LABEL, 
            "");
        set_direct = false;
        incrementing = is_incrementing;
        
        save_source_states(iter);
    }
    
    private void save_source_states(Gee.Iterable<DataView> iter) {
        last_rating_map = new Gee.HashMap<DataSource, Rating>();

        foreach (DataView view in iter) {
            DataSource source = view.get_source();
            last_rating_map[source] = ((MediaSource) source).get_rating();
        }
    }
    
    public override void execute() {
        action_count = 0;
        base.execute();
    }
    
    public override void undo() {
        action_count = 0;
        base.undo();
    }
    
    public override void execute_on_source(DataSource source) {
        if (set_direct)
            ((MediaSource) source).set_rating(new_rating);
        else {
            if (incrementing)
                ((MediaSource) source).increase_rating();
            else
                ((MediaSource) source).decrease_rating();
        }
    }
    
    public override void undo_on_source(DataSource source) {
        ((MediaSource) source).set_rating(last_rating_map[source]);
    }
}

public class SetRawDeveloperCommand : MultipleDataSourceCommand {
    private Gee.HashMap<Photo, RawDeveloper> last_developer_map;
    private Gee.HashMap<Photo, PhotoTransformationState> last_transformation_map;
    private RawDeveloper new_developer;

    public SetRawDeveloperCommand(Gee.Iterable<DataView> iter, RawDeveloper developer) {
        base (iter, _("Setting RAW developer"), _("Restoring previous RAW developer"),
            _("Set Developer"), "");
        new_developer = developer;
        save_source_states(iter);
    }
    
    private void save_source_states(Gee.Iterable<DataView> iter) {
        last_developer_map = new Gee.HashMap<Photo, RawDeveloper>();
        last_transformation_map = new Gee.HashMap<Photo, PhotoTransformationState>();
        
        foreach (DataView view in iter) {
            Photo? photo = view.get_source() as Photo;
            if (is_raw_photo(photo)) {
                last_developer_map[photo] = photo.get_raw_developer();
                last_transformation_map[photo] = photo.save_transformation_state();
            }
        }
    }
    
    public override void execute() {
        base.execute();
    }
    
    public override void undo() {
        base.undo();
    }
    
    public override void execute_on_source(DataSource source) {
        Photo? photo = source as Photo;
        if (is_raw_photo(photo)) {
            if (new_developer == RawDeveloper.CAMERA && !photo.is_raw_developer_available(RawDeveloper.CAMERA))
                photo.set_raw_developer(RawDeveloper.EMBEDDED);
            else
                photo.set_raw_developer(new_developer);
        }
    }
    
    public override void undo_on_source(DataSource source) {
        Photo? photo = source as Photo;
        if (is_raw_photo(photo)) {
            photo.set_raw_developer(last_developer_map[photo]);
            photo.load_transformation_state(last_transformation_map[photo]);
        }
    }
    
    private bool is_raw_photo(Photo? photo) {
        return photo != null && photo.get_master_file_format() == PhotoFileFormat.RAW;
    }
}

public class AdjustDateTimePhotoCommand : SingleDataSourceCommand {
    private Dateable dateable;
    private Event? prev_event;
    private int64 time_shift;
    private bool modify_original;

    public AdjustDateTimePhotoCommand(Dateable dateable, int64 time_shift, bool modify_original) {
        base(dateable, Resources.ADJUST_DATE_TIME_LABEL, "");

        this.dateable = dateable;
        this.time_shift = time_shift;
        this.modify_original = modify_original;
    }

    public override void execute() {
        set_time(dateable, dateable.get_exposure_time() + (time_t) time_shift);

        prev_event = dateable.get_event();

        ViewCollection all_events = new ViewCollection("tmp");
        
        foreach (DataObject dobj in Event.global.get_all()) {
            Event event = dobj as Event;
            if (event != null) {
                all_events.add(new EventView(event));
            }
        }
        Event.generate_single_event(dateable, all_events, null);
    }

    public override void undo() {
        set_time(dateable, dateable.get_exposure_time() - (time_t) time_shift);

        dateable.set_event(prev_event);
    }

    private void set_time(Dateable dateable, time_t exposure_time) {
        if (modify_original && dateable is Photo) {
            try {
                ((Photo)dateable).set_exposure_time_persistent(exposure_time);
            } catch(GLib.Error err) {
                AppWindow.error_message(_("Original photo could not be adjusted."));
            }
        } else {
            dateable.set_exposure_time(exposure_time);
        }
    }
}

public class AdjustDateTimePhotosCommand : MultipleDataSourceCommand {
    private int64 time_shift;
    private bool keep_relativity;
    private bool modify_originals;
    private Gee.Map<Dateable, Event?> prev_events;

    // used when photos are batch changed instead of shifted uniformly
    private time_t? new_time = null;
    private Gee.HashMap<Dateable, time_t?> old_times;
    private Gee.ArrayList<Dateable> error_list;

    public AdjustDateTimePhotosCommand(Gee.Iterable<DataView> iter, int64 time_shift,
        bool keep_relativity, bool modify_originals) {
        base(iter, _("Adjusting Date and Time"), _("Undoing Date and Time Adjustment"),
            Resources.ADJUST_DATE_TIME_LABEL, "");

        this.time_shift = time_shift;
        this.keep_relativity = keep_relativity;
        this.modify_originals = modify_originals;

        // TODO: implement modify originals option

        prev_events = new Gee.HashMap<Dateable, Event?>();

        // this should be replaced by a first function when we migrate to Gee's List
        foreach (DataView view in iter) {
            prev_events.set(view.get_source() as Dateable, (view.get_source() as MediaSource).get_event());
            
            if (new_time == null) {
                new_time = ((Dateable) view.get_source()).get_exposure_time() +
                    (time_t) time_shift;
                break;
            }
        }

        old_times = new Gee.HashMap<Dateable, time_t?>();
    }

    public override void execute() {
        error_list = new Gee.ArrayList<Dateable>();
        base.execute();
        
        if (error_list.size > 0) {
            multiple_object_error_dialog(error_list, 
                ngettext("One original photo could not be adjusted.",
                "The following original photos could not be adjusted.", error_list.size), 
                _("Time Adjustment Error"));
        }

        ViewCollection all_events = new ViewCollection("tmp");

        foreach (Dateable d in prev_events.keys) {
                foreach (DataObject dobj in Event.global.get_all()) {
                Event event = dobj as Event;
                if (event != null) {
                    all_events.add(new EventView(event));
                }
            }
            Event.generate_single_event(d, all_events, null);
        }
    }

    public override void undo() {
        error_list = new Gee.ArrayList<Dateable>();
        base.undo();

        if (error_list.size > 0) {
            multiple_object_error_dialog(error_list, 
                ngettext("Time adjustments could not be undone on the following photo file.",
                "Time adjustments could not be undone on the following photo files.", 
                error_list.size), _("Time Adjustment Error"));
        }
    }

    private void set_time(Dateable dateable, time_t exposure_time) {
        // set_exposure_time_persistent wouldn't work on videos,
        // since we can't actually write them from inside shotwell,
        // so check whether we're working on a Photo or a Video
        if (modify_originals && (dateable is Photo)) {
            try {
                ((Photo) dateable).set_exposure_time_persistent(exposure_time);
            } catch(GLib.Error err) {
                error_list.add(dateable);
            }
        } else {
            // modifying originals is disabled, or this is a
            // video
            dateable.set_exposure_time(exposure_time);
        }
    }

    public override void execute_on_source(DataSource source) {
        Dateable dateable = ((Dateable) source);

        if (keep_relativity && dateable.get_exposure_time() != 0) {
            set_time(dateable, dateable.get_exposure_time() + (time_t) time_shift);
        } else {
            old_times.set(dateable, dateable.get_exposure_time());
            set_time(dateable, new_time);
        }

        ViewCollection all_events = new ViewCollection("tmp");

        foreach (DataObject dobj in Event.global.get_all()) {
            Event event = dobj as Event;
            if (event != null) {
                all_events.add(new EventView(event));
            }
        }
        Event.generate_single_event(dateable, all_events, null);
    }

    public override void undo_on_source(DataSource source) {
        Dateable photo = ((Dateable) source);

        if (old_times.has_key(photo)) {
            set_time(photo, old_times.get(photo));
            old_times.unset(photo);
        } else {
            set_time(photo, photo.get_exposure_time() - (time_t) time_shift);
        }
        
        (source as MediaSource).set_event(prev_events.get(source as Dateable));
    }
}

public class AddTagsCommand : PageCommand {
    private Gee.HashMap<SourceProxy, Gee.ArrayList<MediaSource>> map =
        new Gee.HashMap<SourceProxy, Gee.ArrayList<MediaSource>>();
    
    public AddTagsCommand(string[] paths, Gee.Collection<MediaSource> sources) {
        base (Resources.add_tags_label(paths), "");
        
        // load/create the tags here rather than in execute() so that we can merely use the proxy
        // to access it ... this is important with the redo() case, where the tags may have been
        // created by another proxy elsewhere
        foreach (string path in paths) {
            Gee.List<string> paths_to_create =
                HierarchicalTagUtilities.enumerate_parent_paths(path);
            paths_to_create.add(path);
            
            foreach (string create_path in paths_to_create) {
                Tag tag = Tag.for_path(create_path);
                SourceProxy tag_proxy = tag.get_proxy();
                
                // for each Tag, only attach sources which are not already attached, otherwise undo()
                // will not be symmetric
                Gee.ArrayList<MediaSource> add_sources = new Gee.ArrayList<MediaSource>();
                foreach (MediaSource source in sources) {
                    if (!tag.contains(source))
                        add_sources.add(source);
                }
                
                if (add_sources.size > 0) {
                    tag_proxy.broken.connect(on_proxy_broken);
                    map.set(tag_proxy, add_sources);
                }
            }
        }
        
        LibraryPhoto.global.item_destroyed.connect(on_source_destroyed);
        Video.global.item_destroyed.connect(on_source_destroyed);
    }
    
    ~AddTagsCommand() {
        foreach (SourceProxy tag_proxy in map.keys)
            tag_proxy.broken.disconnect(on_proxy_broken);
        
        LibraryPhoto.global.item_destroyed.disconnect(on_source_destroyed);
        Video.global.item_destroyed.disconnect(on_source_destroyed);
    }
    
    public override void execute() {
        foreach (SourceProxy tag_proxy in map.keys)
            ((Tag) tag_proxy.get_source()).attach_many(map.get(tag_proxy));
    }
    
    public override void undo() {
        foreach (SourceProxy tag_proxy in map.keys) {
            Tag tag = (Tag) tag_proxy.get_source();

            tag.detach_many(map.get(tag_proxy));
        }
    }
    
    private void on_source_destroyed(DataSource source) {
        foreach (Gee.ArrayList<MediaSource> sources in map.values) {
            if (sources.contains((MediaSource) source)) {
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
    
    // NOTE: new_name should be a name, not a path
    public RenameTagCommand(Tag tag, string new_name) {
        base (tag, Resources.rename_tag_label(tag.get_user_visible_name(), new_name),
            tag.get_name());
        
        old_name = tag.get_user_visible_name();
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
    Gee.List<SourceProxy>? recursive_victim_proxies = null;

    public DeleteTagCommand(Tag tag) {
        base (tag, Resources.delete_tag_label(tag.get_user_visible_name()), tag.get_name());
    }
    
    protected override void execute_on_source(DataSource source) {
        Tag tag = (Tag) source;
        
        // process children first, if any
        Gee.List<Tag> recursive_victims = tag.get_hierarchical_children();
        if (recursive_victims.size > 0) {
            // save proxies for these Tags and then delete, in order .. can't use mark_many() or
            // add_proxyables() here because they make no guarantee of order
            recursive_victim_proxies = new Gee.ArrayList<SourceProxy>();
            foreach (Tag victim in recursive_victims) {
                SourceProxy proxy = victim.get_proxy();
                proxy.broken.connect(on_proxy_broken);
                recursive_victim_proxies.add(proxy);
                
                Tag.global.destroy_marked(Tag.global.mark(victim), false);
            }
        }
        
        // destroy parent tag, which is already proxied
        Tag.global.destroy_marked(Tag.global.mark(source), false);
    }
    
    protected override void undo_on_source(DataSource source) {
        // merely instantiating the Tag will rehydrate it ... should always work, because the 
        // undo stack is cleared if the proxy ever breaks
        assert(source is Tag);
        
        // rehydrate the children, in reverse order
        if (recursive_victim_proxies != null) {
            for (int i = recursive_victim_proxies.size - 1; i >= 0; i--) {
                SourceProxy proxy = recursive_victim_proxies.get(i);
                
                DataSource victim_source = proxy.get_source();
                assert(victim_source is Tag);
                
                proxy.broken.disconnect(on_proxy_broken);
            }
            
            recursive_victim_proxies = null;
        }
    }
    
    private void on_proxy_broken() {
        get_command_manager().reset();
    }
}

public class NewChildTagCommand : SimpleProxyableCommand {
    Tag? created_child = null;
    
    public NewChildTagCommand(Tag tag) {
        base (tag, _("Create Tag"), tag.get_name());
    }
    
    protected override void execute_on_source(DataSource source) {
        Tag tag = (Tag) source;
        created_child = tag.create_new_child();
    }
    
    protected override void undo_on_source(DataSource source) {
        Tag.global.destroy_marked(Tag.global.mark(created_child), true);
    }
    
    public Tag get_created_child() {
        assert(created_child != null);
        
        return created_child;
    }
}

public class NewRootTagCommand : PageCommand {
    SourceProxy? created_proxy = null;
    
    public NewRootTagCommand() {
        base (_("Create Tag"), "");
    }
    
    protected override void execute() {
        if (created_proxy == null)
            created_proxy = Tag.create_new_root().get_proxy();
        else
            created_proxy.get_source();
    }
    
    protected override void undo() {
        Tag.global.destroy_marked(Tag.global.mark(created_proxy.get_source()), true);
    }
    
    public Tag get_created_tag() {
        return (Tag) created_proxy.get_source();
    }
}

public class ReparentTagCommand : PageCommand {
    string from_path;
    string to_path;
    string? to_path_parent_path;
    Gee.List<SourceProxy>? src_before_state = null;
    Gee.List<SourceProxy>? dest_before_state = null;
    Gee.List<SourceProxy>? after_state = null;
    Gee.HashSet<MediaSource> sources_in_play = new Gee.HashSet<MediaSource>();
    Gee.Map<string, Gee.Set<MediaSource>> dest_parent_attachments = null;
    Gee.Map<string, Gee.Set<MediaSource>> src_parent_detachments = null;
    Gee.Map<string, Gee.Set<MediaSource>> in_play_child_structure = null;
    Gee.Map<string, Gee.Set<MediaSource>> existing_dest_child_structure = null;
    Gee.Set<MediaSource>? existing_dest_membership = null;
    bool to_path_exists = false;
    
    public ReparentTagCommand(Tag tag, string new_parent_path) {
        base (_("Move Tag “%s”").printf(tag.get_user_visible_name()), "");

        this.from_path = tag.get_path();

        bool has_children = (tag.get_hierarchical_children().size > 0);
        string basename = tag.get_user_visible_name();
        
        if (new_parent_path == Tag.PATH_SEPARATOR_STRING)
            this.to_path = (has_children) ? (Tag.PATH_SEPARATOR_STRING + basename) : basename;
        else if (new_parent_path.has_prefix(Tag.PATH_SEPARATOR_STRING))
            this.to_path = new_parent_path + Tag.PATH_SEPARATOR_STRING + basename;
        else
            this.to_path = Tag.PATH_SEPARATOR_STRING + new_parent_path + Tag.PATH_SEPARATOR_STRING +
                basename;
        
        string? new_to_path = HierarchicalTagUtilities.get_root_path_form(to_path);
        if (new_to_path != null)
            this.to_path = new_to_path;
        
        if (Tag.global.exists(this.to_path))
            to_path_exists = true;

        sources_in_play.add_all(tag.get_sources());
        
        LibraryPhoto.global.items_destroyed.connect(on_items_destroyed);
        Video.global.items_destroyed.connect(on_items_destroyed);
    }
    
    ~ReparentTagCommand() {
        LibraryPhoto.global.items_destroyed.disconnect(on_items_destroyed);
        Video.global.items_destroyed.disconnect(on_items_destroyed);
    }
    
    private void on_items_destroyed(Gee.Collection<DataSource> destroyed) {
        foreach (DataSource source in destroyed) {
            if (sources_in_play.contains((MediaSource) source))
                get_command_manager().reset();
        }
    }
    
    private Gee.Map<string, Gee.Set<MediaSource>> get_child_structure_at(string client_path) {
        string? path = HierarchicalTagUtilities.get_root_path_form(client_path);
        path = (path != null) ? path : client_path;

        Gee.Map<string, Gee.Set<MediaSource>> result =
            new Gee.HashMap<string, Gee.Set<MediaSource>>();

        if (!Tag.global.exists(path))
            return result;
            
        Tag tag = Tag.for_path(path);
        
        string path_prefix = tag.get_path() + Tag.PATH_SEPARATOR_STRING;
        foreach (Tag t in tag.get_hierarchical_children()) {
            string child_subpath = t.get_path().replace(path_prefix, "");

            result.set(child_subpath, new Gee.HashSet<MediaSource>());
            result.get(child_subpath).add_all(t.get_sources());
        }
        
        return result;
    }
    
    private void restore_child_attachments_at(string client_path,
        Gee.Map<string, Gee.Set<MediaSource>> child_structure) {
        
        string? new_path = HierarchicalTagUtilities.get_root_path_form(client_path);
        string path = (new_path != null) ? new_path : client_path;
        
        assert(Tag.global.exists(path));
        Tag tag = Tag.for_path(path);
        
        foreach (string child_subpath in child_structure.keys) {
            string child_path = tag.get_path() + Tag.PATH_SEPARATOR_STRING + child_subpath;

            if (!tag.get_path().has_prefix(Tag.PATH_SEPARATOR_STRING)) {
                tag.promote();
                child_path = tag.get_path() + Tag.PATH_SEPARATOR_STRING + child_subpath;
            }
            
            assert(Tag.global.exists(child_path));
            
            foreach (MediaSource s in child_structure.get(child_subpath))
                Tag.for_path(child_path).attach(s);
        }
    }
    
    private void reattach_in_play_sources_at(string client_path) {
        string? new_path = HierarchicalTagUtilities.get_root_path_form(client_path);
        string path = (new_path != null) ? new_path : client_path;
        
        assert(Tag.global.exists(path));
        
        Tag tag = Tag.for_path(path);
        
        foreach (MediaSource s in sources_in_play)
            tag.attach(s);
    }
    
    private void save_before_state() {
        assert(src_before_state == null);
        assert(dest_before_state == null);
        
        src_before_state = new Gee.ArrayList<SourceProxy>();
        dest_before_state = new Gee.ArrayList<SourceProxy>();

        // capture the child structure of the from tag
        assert(in_play_child_structure == null);
        in_play_child_structure = get_child_structure_at(from_path);
        
        // save the state of the from tag
        assert(Tag.global.exists(from_path));
        Tag from_tag = Tag.for_path(from_path);
        src_before_state.add(from_tag.get_proxy());
        
        // capture the child structure of the parent of the to tag, if the to tag has a parent
        Gee.List<string> parent_paths = HierarchicalTagUtilities.enumerate_parent_paths(to_path);
        if (parent_paths.size > 0)
            to_path_parent_path = parent_paths.get(parent_paths.size - 1);
        if (to_path_parent_path != null) {
            assert(existing_dest_child_structure == null);
            existing_dest_child_structure = get_child_structure_at(to_path_parent_path);
        }
        
        // if the to tag doesn't have a parent, then capture the structure of the to tag itself
        if (to_path_parent_path == null) {
            assert(existing_dest_child_structure == null);
            assert(existing_dest_membership == null);
            existing_dest_child_structure = get_child_structure_at(to_path);
            existing_dest_membership = new Gee.HashSet<MediaSource>();
            existing_dest_membership.add_all(Tag.for_path(to_path).get_sources());
        }
        
        // save the state of the to tag's parent
        if (to_path_parent_path != null) {
            string? new_tpp = HierarchicalTagUtilities.get_root_path_form(to_path_parent_path);
            to_path_parent_path = (new_tpp != null) ? new_tpp : to_path_parent_path;
            assert(Tag.global.exists(to_path_parent_path));
            dest_before_state.add(Tag.for_path(to_path_parent_path).get_proxy());
        }
        
        // if the to tag doesn't have a parent, save the state of the to tag itself
        if (to_path_parent_path == null) {
            dest_before_state.add(Tag.for_path(to_path).get_proxy());
        }

        // save the state of the children of the from tag in order from most basic to most derived
        Gee.List<Tag> from_children = from_tag.get_hierarchical_children();
        for (int i = from_children.size - 1; i >= 0; i--)
            src_before_state.add(from_children.get(i).get_proxy());

        // save the state of the children of the to tag's parent in order from most basic to most
        // derived
        if (to_path_parent_path != null) {
            Gee.List<Tag> to_children = Tag.for_path(to_path_parent_path).get_hierarchical_children();
            for (int i = to_children.size - 1; i >= 0; i--)
                dest_before_state.add(to_children.get(i).get_proxy());
        }
        
        // if the to tag doesn't have a parent, then save the state of the to tag's direct
        // children, if any
        if (to_path_parent_path == null) {
            Gee.List<Tag> to_children = Tag.for_path(to_path).get_hierarchical_children();
            for (int i = to_children.size - 1; i >= 0; i--)
                dest_before_state.add(to_children.get(i).get_proxy());
        }
    }
    
    private void restore_before_state() {
        assert(src_before_state != null);
        assert(existing_dest_child_structure != null);
        
        // unwind the destination tree to its pre-merge state
        if (to_path_parent_path != null) {
            string? new_tpp = HierarchicalTagUtilities.get_root_path_form(to_path_parent_path);
            to_path_parent_path = (new_tpp != null) ? new_tpp : to_path_parent_path;
        }

        string unwind_target = (to_path_parent_path != null) ? to_path_parent_path : to_path;
        foreach (Tag t in Tag.for_path(unwind_target).get_hierarchical_children()) {
            string child_subpath = t.get_path().replace(unwind_target, "");
            if (child_subpath.has_prefix(Tag.PATH_SEPARATOR_STRING))
                child_subpath = child_subpath.substring(1);

            if (!existing_dest_child_structure.has_key(child_subpath)) {
                Tag.global.destroy_marked(Tag.global.mark(t), true);
            } else {
                Gee.Set<MediaSource> starting_sources = new Gee.HashSet<MediaSource>();
                starting_sources.add_all(t.get_sources());
                foreach (MediaSource source in starting_sources)
                    if (!(existing_dest_child_structure.get(child_subpath).contains(source)))
                        t.detach(source);
            }
        }
        
        for (int i = 0; i < src_before_state.size; i++)
            src_before_state.get(i).get_source();

        for (int i = 0; i < dest_before_state.size; i++)
            dest_before_state.get(i).get_source();

        if (to_path_parent_path != null) {
            string? new_path = HierarchicalTagUtilities.get_root_path_form(to_path_parent_path);
            string path = (new_path != null) ? new_path : to_path_parent_path;  

            assert(Tag.global.exists(path));
            
            Tag t = Tag.for_path(path);

            Gee.List<Tag> kids = t.get_hierarchical_children();
            foreach (Tag kidtag in kids)
                kidtag.detach_many(kidtag.get_sources());

            restore_child_attachments_at(path, existing_dest_child_structure);
        } else {
            assert(existing_dest_membership != null);
            Tag.for_path(to_path).detach_many(Tag.for_path(to_path).get_sources());
            Tag.for_path(to_path).attach_many(existing_dest_membership);
            
            Gee.List<Tag> kids = Tag.for_path(to_path).get_hierarchical_children();
            foreach (Tag kidtag in kids)
                kidtag.detach_many(kidtag.get_sources());
            
            restore_child_attachments_at(to_path, existing_dest_child_structure);
        }
    }
    
    private void save_after_state() {
        assert(after_state == null);
        
        after_state = new Gee.ArrayList<SourceProxy>();
        
        // save the state of the to tag
        assert(Tag.global.exists(to_path));
        Tag to_tag = Tag.for_path(to_path);
        after_state.add(to_tag.get_proxy());
        
        // save the state of the children of the to tag in order from most basic to most derived
        Gee.List<Tag> to_children = to_tag.get_hierarchical_children();
        for (int i = to_children.size - 1; i >= 0; i--)
            after_state.add(to_children.get(i).get_proxy());
    }
    
    private void restore_after_state() {
        assert(after_state != null);
        
        for (int i = 0; i < after_state.size; i++)
            after_state.get(i).get_source();
    }

    private void prepare_parent(string path) {
        // find our new parent tag (if one exists) and promote it
        Tag? new_parent = null;
        if (path.has_prefix(Tag.PATH_SEPARATOR_STRING)) {
            Gee.List<string> parent_paths = HierarchicalTagUtilities.enumerate_parent_paths(path);
            if (parent_paths.size > 0) {
                string immediate_parent_path = parent_paths.get(parent_paths.size - 1);
                if (Tag.global.exists(immediate_parent_path))
                    new_parent = Tag.for_path(immediate_parent_path);
                else if (Tag.global.exists(immediate_parent_path.substring(1)))
                    new_parent = Tag.for_path(immediate_parent_path.substring(1));
                else
                    assert_not_reached();
            }
        }    
        if (new_parent != null)
            new_parent.promote();
    }
    
    private void do_source_parent_detachments() {
        assert(Tag.global.exists(from_path));
        Tag from_tag = Tag.for_path(from_path);
        
        // see if this copy operation will detach any media items from the source tag's parents
        if (src_parent_detachments == null) {
            src_parent_detachments = new Gee.HashMap<string, Gee.Set<MediaSource>>();
            foreach (MediaSource source in from_tag.get_sources()) {
                Tag? current_parent = from_tag.get_hierarchical_parent();
                int running_attach_count = from_tag.get_attachment_count(source) + 1;
                while (current_parent != null) {
                    string current_parent_path = current_parent.get_path();
                    if (!src_parent_detachments.has_key(current_parent_path))
                        src_parent_detachments.set(current_parent_path, new Gee.HashSet<MediaSource>());

                    int curr_parent_attach_count = current_parent.get_attachment_count(source);
                    
                    assert (curr_parent_attach_count >= running_attach_count);
                    
                    // if this parent tag has no other child tags that the current media item is
                    // attached to
                    if (curr_parent_attach_count == running_attach_count)
                        src_parent_detachments.get(current_parent_path).add(source);

                    running_attach_count++;
                    current_parent = current_parent.get_hierarchical_parent();
                }
            }
        }
        
        // perform collected detachments
        foreach (string p in src_parent_detachments.keys)
            foreach (MediaSource s in src_parent_detachments.get(p))
                Tag.for_path(p).detach(s);
    }
    
    private void do_source_parent_reattachments() {
        assert(src_parent_detachments != null);
        
        foreach (string p in src_parent_detachments.keys)
            foreach (MediaSource s in src_parent_detachments.get(p))
                Tag.for_path(p).attach(s);
    }
    
    private void do_destination_parent_detachments() {
        assert(dest_parent_attachments != null);
        
        foreach (string p in dest_parent_attachments.keys)
            foreach (MediaSource s in dest_parent_attachments.get(p))
                Tag.for_path(p).detach(s);
    }
    
    private void do_destination_parent_reattachments() {
        assert(dest_parent_attachments != null);
        
        foreach (string p in dest_parent_attachments.keys)
            foreach (MediaSource s in dest_parent_attachments.get(p))
                Tag.for_path(p).attach(s);
    }
    
    private void copy_subtree(string from, string to) {
        assert(Tag.global.exists(from));
        Tag from_tag = Tag.for_path(from);
        
        // get (or create) a tag for the destination path
        Tag to_tag = Tag.for_path(to);
        
        // see if this copy operation will attach any new media items to the destination's parents,
        // if so, record them for later undo/redo
        dest_parent_attachments = new Gee.HashMap<string, Gee.Set<MediaSource>>();
        foreach (MediaSource source in from_tag.get_sources()) {
            Tag? current_parent = to_tag.get_hierarchical_parent();
            while (current_parent != null) {
                string current_parent_path = current_parent.get_path();
                if (!dest_parent_attachments.has_key(current_parent_path))
                    dest_parent_attachments.set(current_parent_path, new Gee.HashSet<MediaSource>());

                if (!current_parent.contains(source))
                    dest_parent_attachments.get(current_parent_path).add(source);
            
                current_parent = current_parent.get_hierarchical_parent();
            }
        }
        
        foreach (MediaSource source in from_tag.get_sources())
            to_tag.attach(source);

        // loop through the children of the from tag in order from most basic to most derived,
        // creating corresponding child tags on the to tag and attaching corresponding sources
        Gee.List<Tag> from_children = from_tag.get_hierarchical_children();
        for (int i = from_children.size - 1; i >= 0; i--) {
            Tag from_child = from_children.get(i);
            
            string child_subpath = from_child.get_path().replace(from + Tag.PATH_SEPARATOR_STRING,
                "");

            Tag to_child = Tag.for_path(to_tag.get_path() + Tag.PATH_SEPARATOR_STRING +
                child_subpath);

            foreach (MediaSource source in from_child.get_sources())
                to_child.attach(source);
        }
    }
    
    private void destroy_subtree(string client_path) {
        string? victim_path = HierarchicalTagUtilities.get_root_path_form(client_path);
        if (victim_path == null)
            victim_path = client_path;
        
        if (!Tag.global.exists(victim_path))
            return;
            
        Tag victim = Tag.for_path(victim_path);

        // destroy the children of the victim in order from most derived to most basic
        Gee.List<Tag> victim_children = victim.get_hierarchical_children();
        for (int i = 0; i < victim_children.size; i++)
            Tag.global.destroy_marked(Tag.global.mark(victim_children.get(i)), true);
        
        // destroy the victim itself
        Tag.global.destroy_marked(Tag.global.mark(victim), true);
    }
    
    public override void execute() {
        if (after_state == null) {
            save_before_state();
            
            prepare_parent(to_path);

            copy_subtree(from_path, to_path);

            save_after_state();

            do_source_parent_detachments();

            destroy_subtree(from_path);
        } else {
            prepare_parent(to_path);
            
            restore_after_state();
            
            restore_child_attachments_at(to_path, in_play_child_structure);
            reattach_in_play_sources_at(to_path);

            do_source_parent_detachments();
            do_destination_parent_reattachments();

            destroy_subtree(from_path);
        }
    }
    
    public override void undo() {
        assert(src_before_state != null);
        
        prepare_parent(from_path);

        restore_before_state();
        
        if (!to_path_exists)
            destroy_subtree(to_path);
        
        restore_child_attachments_at(from_path, in_play_child_structure);
        reattach_in_play_sources_at(from_path);
        
        do_source_parent_reattachments();
        do_destination_parent_detachments();
        
        HierarchicalTagUtilities.cleanup_root_path(to_path);
        HierarchicalTagUtilities.cleanup_root_path(from_path);
        if (to_path_parent_path != null)
            HierarchicalTagUtilities.cleanup_root_path(to_path_parent_path);
    }
}

public class ModifyTagsCommand : SingleDataSourceCommand {
    private MediaSource media;
    private Gee.ArrayList<SourceProxy> to_add = new Gee.ArrayList<SourceProxy>();
    private Gee.ArrayList<SourceProxy> to_remove = new Gee.ArrayList<SourceProxy>();
    
    public ModifyTagsCommand(MediaSource media, Gee.Collection<Tag> new_tag_list) {
        base (media, Resources.MODIFY_TAGS_LABEL, "");
        
        this.media = media;
        
        // Prepare to remove all existing tags, if any, from the current media source.
        Gee.List<Tag>? original_tags = Tag.global.fetch_for_source(media);
        if (original_tags != null) {
            foreach (Tag tag in original_tags) {
                SourceProxy proxy = tag.get_proxy();
                to_remove.add(proxy);
                proxy.broken.connect(on_proxy_broken);
            }
        }
        
        // Prepare to add all new tags; remember, if a tag is added, its parent must be
        // added as well. So enumerate all paths to add and then get the tags for them.
        Gee.SortedSet<string> new_paths = new Gee.TreeSet<string>();
        foreach (Tag new_tag in new_tag_list) {
            string new_tag_path = new_tag.get_path();

            new_paths.add(new_tag_path);
            new_paths.add_all(HierarchicalTagUtilities.enumerate_parent_paths(new_tag_path));
        }
        
        foreach (string path in new_paths) {
            assert(Tag.global.exists(path));

            SourceProxy proxy = Tag.for_path(path).get_proxy();
            to_add.add(proxy);
            proxy.broken.connect(on_proxy_broken);
        }
    }
    
    ~ModifyTagsCommand() {
        foreach (SourceProxy proxy in to_add)
            proxy.broken.disconnect(on_proxy_broken);
        
        foreach (SourceProxy proxy in to_remove)
            proxy.broken.disconnect(on_proxy_broken);
    }
    
    public override void execute() {
        foreach (SourceProxy proxy in to_remove)
            ((Tag) proxy.get_source()).detach(media);
            
        foreach (SourceProxy proxy in to_add)
            ((Tag) proxy.get_source()).attach(media);
    }
    
    public override void undo() {
        foreach (SourceProxy proxy in to_add)
            ((Tag) proxy.get_source()).detach(media);
        
        foreach (SourceProxy proxy in to_remove)
            ((Tag) proxy.get_source()).attach(media);
    }
    
    private void on_proxy_broken() {
        get_command_manager().reset();
    }
}

public class TagUntagPhotosCommand : SimpleProxyableCommand {
    private Gee.Collection<MediaSource> sources;
    private bool attach;
    private Gee.MultiMap<Tag, MediaSource>? detached_from = null;
    private Gee.List<Tag>? attached_to = null;
    
    public TagUntagPhotosCommand(Tag tag, Gee.Collection<MediaSource> sources, int count, bool attach) {
        base (tag,
            attach ? Resources.tag_photos_label(tag.get_user_visible_name(), count) 
                : Resources.untag_photos_label(tag.get_user_visible_name(), count),
            tag.get_name());
        
        this.sources = sources;
        this.attach = attach;
        
        LibraryPhoto.global.item_destroyed.connect(on_source_destroyed);
        Video.global.item_destroyed.connect(on_source_destroyed);
    }
    
    ~TagUntagPhotosCommand() {
        LibraryPhoto.global.item_destroyed.disconnect(on_source_destroyed);
        Video.global.item_destroyed.disconnect(on_source_destroyed);
    }
    
    public override void execute_on_source(DataSource source) {
        if (attach)
            do_attach((Tag) source);
        else
            do_detach((Tag) source);
    }
    
    public override void undo_on_source(DataSource source) {
        if (attach)
            do_detach((Tag) source);
        else
            do_attach((Tag) source);
    }
    
    private void do_attach(Tag tag) {
        // if not attaching previously detached Tags, attach and done
        if (detached_from == null) {
            tag.attach_many(sources);
            
            attached_to = new Gee.ArrayList<Tag>();
            
            Tag curr_tmp = tag;
            
            while (curr_tmp != null) {
                attached_to.add(curr_tmp);
                curr_tmp = curr_tmp.get_hierarchical_parent();
            }
            
            return;
        }
        
        // reattach
        foreach (Tag detached_tag in detached_from.get_all_keys())
            detached_tag.attach_many(detached_from.get(detached_tag));
        
        detached_from = null;
        clear_added_proxies();
    }
    
    private void do_detach(Tag tag) {
        if (attached_to == null) {
            // detaching a MediaSource from a Tag may result in the MediaSource being detached from
            // many tags (due to hierarchical tagging), so save the MediaSources for each detached
            // Tag for reversing the process
            detached_from = tag.detach_many(sources);
            
            // since the "master" Tag (supplied in the ctor) is not necessarily the only one being
            // saved, add proxies for all of the other ones as well
            add_proxyables(detached_from.get_keys());
        } else {
            foreach (Tag t in attached_to) {
                foreach (MediaSource ms in sources) {
                    // is this photo/video attached to this tag elsewhere?
                    if (t.get_attachment_count(ms) < 2) {
                        //no, remove it.
                        t.detach(ms);
                    }
                }
            }
        }
    }
    
    private void on_source_destroyed(DataSource source) {
        debug("on_source_destroyed: %s", source.to_string());
        if (sources.contains((MediaSource) source))
            get_command_manager().reset();
    }
}

public class RenameSavedSearchCommand : SingleDataSourceCommand {
    private SavedSearch search;
    private string old_name;
    private string new_name;
    
    public RenameSavedSearchCommand(SavedSearch search, string new_name) {
        base (search, Resources.rename_search_label(search.get_name(), new_name), search.get_name());
            
        this.search = search;
        old_name = search.get_name();
        this.new_name = new_name;
    }
    
    public override void execute() {
        if (!search.rename(new_name))
            AppWindow.error_message(Resources.rename_search_exists_message(new_name));
    }

    public override void undo() {
        if (!search.rename(old_name))
            AppWindow.error_message(Resources.rename_search_exists_message(old_name));
    }
}

public class DeleteSavedSearchCommand : SingleDataSourceCommand {
    private SavedSearch search;
    
    public DeleteSavedSearchCommand(SavedSearch search) {
        base (search, Resources.delete_search_label(search.get_name()), search.get_name());
            
        this.search = search;
    }
    
    public override void execute() {
        SavedSearchTable.get_instance().remove(search);
    }

    public override void undo() {
        search.reconstitute();
    }
}

public class TrashUntrashPhotosCommand : PageCommand {
    private Gee.Collection<MediaSource> sources;
    private bool to_trash;
    
    public TrashUntrashPhotosCommand(Gee.Collection<MediaSource> sources, bool to_trash) {
        base (
            to_trash ? _("Move Photos to Trash") : _("Restore Photos from Trash"),
            to_trash ? _("Move the photos to the Shotwell trash") : _("Restore the photos back to the Shotwell library"));
        
        this.sources = sources;
        this.to_trash = to_trash;
        
        LibraryPhoto.global.item_destroyed.connect(on_photo_destroyed);
        Video.global.item_destroyed.connect(on_photo_destroyed);
    }
    
    ~TrashUntrashPhotosCommand() {
        LibraryPhoto.global.item_destroyed.disconnect(on_photo_destroyed);
        Video.global.item_destroyed.disconnect(on_photo_destroyed);
    }
    
    private ProgressDialog? get_progress_dialog(bool to_trash) {
        if (sources.size <= 5)
            return null;
        
        ProgressDialog dialog = new ProgressDialog(AppWindow.get_instance(),
            to_trash ? _("Moving Photos to Trash") : _("Restoring Photos From Trash"));
        dialog.update_display_every((sources.size / 5).clamp(2, 10));
        
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
        int count = sources.size;
        
        LibraryPhoto.global.transaction_controller.begin();
        Video.global.transaction_controller.begin();
        
        foreach (MediaSource source in sources) {
            source.trash();
            if (monitor != null)
                monitor(++ctr, count);
        }
        
        LibraryPhoto.global.transaction_controller.commit();
        Video.global.transaction_controller.commit();
    }
    
    private void untrash(ProgressMonitor? monitor) {
        int ctr = 0;
        int count = sources.size;
        
        LibraryPhoto.global.transaction_controller.begin();
        Video.global.transaction_controller.begin();
        
        foreach (MediaSource source in sources) {
            source.untrash();
            if (monitor != null)
                monitor(++ctr, count);
        }
        
        LibraryPhoto.global.transaction_controller.commit();
        Video.global.transaction_controller.commit();
    }
    
    private void on_photo_destroyed(DataSource source) {
        // in this case, don't need to reset the command manager, simply remove the photo from the
        // internal list and allow the others to be moved to and from the trash
        sources.remove((MediaSource) source);
        
        // however, if all photos missing, then remove this from the command stack, and there's
        // only one way to do that
        if (sources.size == 0)
            get_command_manager().reset();
    }
}

public class FlagUnflagCommand : MultipleDataSourceAtOnceCommand {
    private const int MIN_PROGRESS_BAR_THRESHOLD = 1000;
    private const string FLAG_SELECTED_STRING = _("Flag selected photos");
    private const string UNFLAG_SELECTED_STRING = _("Unflag selected photos");
    private const string FLAG_PROGRESS = _("Flagging selected photos");
    private const string UNFLAG_PROGRESS = _("Unflagging selected photos");
    
    private bool flag;
    private ProgressDialog progress_dialog = null;
    
    public FlagUnflagCommand(Gee.Collection<MediaSource> sources, bool flag) {
        base (sources,
            flag ? _("Flag") : _("Unflag"),
            flag ? FLAG_SELECTED_STRING : UNFLAG_SELECTED_STRING);
        
        this.flag = flag;
        
        if (sources.size >= MIN_PROGRESS_BAR_THRESHOLD) {
            progress_dialog = new ProgressDialog(null,
                flag ? FLAG_PROGRESS : UNFLAG_PROGRESS);
            
            progress_dialog.show_all();
        }
    }
    
    public override void execute_on_all(Gee.Collection<DataSource> sources) {
        int num_processed = 0;
        
        foreach (DataSource source in sources) {
            flag_unflag(source, flag);
            
            num_processed++;
            
            if (progress_dialog != null) {
                progress_dialog.set_fraction(num_processed, sources.size);
                progress_dialog.queue_draw();
                spin_event_loop();
            }
        }
        
        if (progress_dialog != null)
            progress_dialog.hide();
    }
    
    public override void undo_on_all(Gee.Collection<DataSource> sources) {
        foreach (DataSource source in sources)
            flag_unflag(source, !flag);
    }
    
    private void flag_unflag(DataSource source, bool flag) {
        Flaggable? flaggable = source as Flaggable;
        if (flaggable != null) {
            if (flag)
                flaggable.mark_flagged();
            else
                flaggable.mark_unflagged();
        }
    }
}

#if ENABLE_FACES
public class RemoveFacesFromPhotosCommand : SimpleProxyableCommand {
    private Gee.Map<MediaSource, string> map_source_geometry = new Gee.HashMap<MediaSource, string>();
    
    public RemoveFacesFromPhotosCommand(Face face, Gee.Collection<MediaSource> sources) {
        base (face,
            Resources.remove_face_from_photos_label(face.get_name(), sources.size),
            face.get_name());
        
        foreach (MediaSource source in sources) {
            FaceLocation? face_location =
                FaceLocation.get_face_location(face.get_face_id(), ((Photo) source).get_photo_id());
            assert(face_location != null);
            
            this.map_source_geometry.set(source, face_location.get_serialized_geometry());
        }
        
        LibraryPhoto.global.item_destroyed.connect(on_source_destroyed);
        Video.global.item_destroyed.connect(on_source_destroyed);
    }
    
    ~RemoveFacesFromPhotosCommand() {
        LibraryPhoto.global.item_destroyed.disconnect(on_source_destroyed);
        Video.global.item_destroyed.disconnect(on_source_destroyed);
    }
    
    public override void execute_on_source(DataSource source) {
        ((Face) source).detach_many(map_source_geometry.keys);
    }
    
    public override void undo_on_source(DataSource source) {
        Face face = (Face) source;
        
        face.attach_many(map_source_geometry.keys);
        foreach (Gee.Map.Entry<MediaSource, string> entry in map_source_geometry.entries)
            FaceLocation.create(face.get_face_id(), ((Photo) entry.key).get_photo_id(), entry.value);
    }
    
    private void on_source_destroyed(DataSource source) {
        if (map_source_geometry.keys.contains((MediaSource) source))
            get_command_manager().reset();
    }
}

public class RenameFaceCommand : SimpleProxyableCommand {
    private string old_name;
    private string new_name;
    
    public RenameFaceCommand(Face face, string new_name) {
        base (face, Resources.rename_face_label(face.get_name(), new_name), face.get_name());
        
        old_name = face.get_name();
        this.new_name = new_name;
    }
    
    protected override void execute_on_source(DataSource source) {
        if (!((Face) source).rename(new_name))
            AppWindow.error_message(Resources.rename_face_exists_message(new_name));
    }

    protected override void undo_on_source(DataSource source) {
        if (!((Face) source).rename(old_name))
            AppWindow.error_message(Resources.rename_face_exists_message(old_name));
    }
}

public class DeleteFaceCommand : SimpleProxyableCommand {
    private Gee.Map<PhotoID?, string> photo_geometry_map = new Gee.HashMap<PhotoID?, string>
        ((Gee.HashDataFunc)FaceLocation.photo_id_hash, (Gee.EqualDataFunc)FaceLocation.photo_ids_equal);
    
    public DeleteFaceCommand(Face face) {
        base (face, Resources.delete_face_label(face.get_name()), face.get_name());
        
        // we can't use the Gee.Map returned by FaceLocation.get_locations_by_face
        // because it will be modified in execute_on_source
        Gee.Map<PhotoID?, FaceLocation>? temp = FaceLocation.get_locations_by_face(face);
        assert(temp != null);
        foreach (Gee.Map.Entry<PhotoID?, FaceLocation> entry in temp.entries)
            photo_geometry_map.set(entry.key, entry.value.get_serialized_geometry());
    }
    
    protected override void execute_on_source(DataSource source) {
        FaceID face_id = ((Face) source).get_face_id();
        foreach (PhotoID photo_id in photo_geometry_map.keys)
            FaceLocation.destroy(face_id, photo_id);
        
        Face.global.destroy_marked(Face.global.mark(source), false);
    }
    
    protected override void undo_on_source(DataSource source) {
        // merely instantiating the Face will rehydrate it ... should always work, because the 
        // undo stack is cleared if the proxy ever breaks
        assert(source is Face);
        
        foreach (Gee.Map.Entry<PhotoID?, string> entry in photo_geometry_map.entries) {
            Photo? photo = LibraryPhoto.global.fetch(entry.key);
            
            if (photo != null) {
                Face face = (Face) source;
                
                face.attach(photo);
                FaceLocation.create(face.get_face_id(), entry.key, entry.value);
            }
        }
    }
}

public class ModifyFacesCommand : SingleDataSourceCommand {
    private MediaSource media;
    private Gee.ArrayList<SourceProxy> to_add = new Gee.ArrayList<SourceProxy>();
    private Gee.ArrayList<SourceProxy> to_remove = new Gee.ArrayList<SourceProxy>();
    private Gee.Map<SourceProxy, string> to_update = new Gee.HashMap<SourceProxy, string>();
    private Gee.Map<SourceProxy, string> geometries = new Gee.HashMap<SourceProxy, string>();
    
    public ModifyFacesCommand(MediaSource media, Gee.Map<Face, string> new_face_list) {
        base (media, Resources.MODIFY_FACES_LABEL, "");
        
        this.media = media;
        
        // Remove any face that's in the original list but not the new one
        Gee.Collection<Face>? original_faces = Face.global.fetch_for_source(media);
        if (original_faces != null) {
            foreach (Face face in original_faces) {
                if (!new_face_list.keys.contains(face)) {
                    SourceProxy proxy = face.get_proxy();
                    
                    to_remove.add(proxy);
                    proxy.broken.connect(on_proxy_broken);
                    
                    FaceLocation? face_location =
                        FaceLocation.get_face_location(face.get_face_id(), ((Photo) media).get_photo_id());
                    assert(face_location != null);
                    
                    geometries.set(proxy, face_location.get_serialized_geometry());
                }
            }
        }
        
        // Add any face that's in the new list but not the original
        foreach (Gee.Map.Entry<Face, string> entry in new_face_list.entries) {
            if (original_faces == null || !original_faces.contains(entry.key)) {
                SourceProxy proxy = entry.key.get_proxy();
                
                to_add.add(proxy);
                proxy.broken.connect(on_proxy_broken);
                
                geometries.set(proxy, entry.value);
            } else {
                // If it is already in the original list we need to check if it's
                // geometry has changed.
                FaceLocation? face_location =
                    FaceLocation.get_face_location(entry.key.get_face_id(), ((Photo) media).get_photo_id());
                assert(face_location != null);
                
                string old_geometry = face_location.get_serialized_geometry();
                if (old_geometry != entry.value) {
                    SourceProxy proxy = entry.key.get_proxy();
                    
                    to_update.set(proxy, entry.value);
                    proxy.broken.connect(on_proxy_broken);
                    
                    geometries.set(proxy, old_geometry);
                }
            }
        }
    }
    
    ~ModifyFacesCommand() {
        foreach (SourceProxy proxy in to_add)
            proxy.broken.disconnect(on_proxy_broken);
        
        foreach (SourceProxy proxy in to_remove)
            proxy.broken.disconnect(on_proxy_broken);
        
        foreach (SourceProxy proxy in to_update.keys)
            proxy.broken.disconnect(on_proxy_broken);
    }
    
    public override void execute() {
        foreach (SourceProxy proxy in to_add) {
            Face face = (Face) proxy.get_source();
            face.attach(media);
            FaceLocation.create(face.get_face_id(), ((Photo) media).get_photo_id(), geometries.get(proxy));
        }
        
        foreach (SourceProxy proxy in to_remove)
            ((Face) proxy.get_source()).detach(media);
        
        foreach (Gee.Map.Entry<SourceProxy, string> entry in to_update.entries) {
            Face face = (Face) entry.key.get_source();
            FaceLocation.create(face.get_face_id(), ((Photo) media).get_photo_id(), entry.value);
        }
    }
    
    public override void undo() {
        foreach (SourceProxy proxy in to_add)
            ((Face) proxy.get_source()).detach(media);
        
        foreach (SourceProxy proxy in to_remove) {
            Face face = (Face) proxy.get_source();
            face.attach(media);
            FaceLocation.create(face.get_face_id(), ((Photo) media).get_photo_id(), geometries.get(proxy));
        }
        
        foreach (SourceProxy proxy in to_update.keys) {
            Face face = (Face) proxy.get_source();
            FaceLocation.create(face.get_face_id(), ((Photo) media).get_photo_id(), geometries.get(proxy));
        }
    }
    
    private void on_proxy_broken() {
        get_command_manager().reset();
    }
}

#endif
