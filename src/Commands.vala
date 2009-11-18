/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public abstract class SingleDataSourceCommand : Command {
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
        AppWindow.get_command_manager().reset();
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

public abstract class MultipleDataSourceCommand : Command {
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
            AppWindow.get_command_manager().reset();
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

