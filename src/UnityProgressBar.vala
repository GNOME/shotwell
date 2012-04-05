#if UNITY_SUPPORT
public class UnityProgressBar : Object {

    private static Unity.LauncherEntry l = Unity.LauncherEntry.get_for_desktop_id("shotwell.desktop");
    private static UnityProgressBar? visible_uniprobar;
    
    private UnityProgressBarImportance importance;
    private double progress;
    private bool visible;
    
    public UnityProgressBar(UnityProgressBarImportance importance) {
        this.importance = importance;
        progress = 0.0;
        visible = false;
    }

    ~UnityProgressBar () {
        if (visible_uniprobar == this) {
            reset_progress_bar();
        }
    }
    
    public UnityProgressBarImportance get_importance () {
        return importance;
    }
    
    public double get_progress () {
        return progress;
    }
    
    public void set_progress (double percent) {
        progress = percent;
        update_visibility();
    }

    private void update_visibility () {
        if (this.visible) {
            //already a progress bar set
            //overwrite when more important
            if (visible_uniprobar != null) {
                if (visible_uniprobar.importance < this.importance || visible_uniprobar == this) {
                    set_progress_bar(this, progress);
                }
            }
            //set; nothing else there
            else {
                set_progress_bar(this, progress);
            }
        }
    }
    
    public bool get_visible () {
        return visible;
    }
    
    public void set_visible (bool visible) {
        this.visible = visible;
        
        //if not visible and currently displayed, remove Unitys progress bar
        if (!visible && visible_uniprobar == this)
            reset_progress_bar();
        
        //update_visibility if this progress bar wants to be drawn
        if (visible)
            update_visibility();
    }
    
    public void reset () {
        set_visible(false);
        progress = 0.0;
    }
    
    private static void set_progress_bar (UnityProgressBar uniprobar, double percent) {
        //set new visible ProgressBar
        visible_uniprobar = uniprobar;
        if (!l.progress_visible)
            l.progress_visible = true;
        l.progress = percent;
    }
    
    private static void reset_progress_bar () {
        //reset to default values
        visible_uniprobar = null;
        l.progress = 0.0;
        l.progress_visible = false;
    }
}

public enum UnityProgressBarImportance {
    LOW,
    MEDIUM,
    HIGH
}
#endif
