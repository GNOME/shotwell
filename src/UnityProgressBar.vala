/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

#if UNITY_SUPPORT
public class UnityProgressBar : Object {

    private static Unity.LauncherEntry l = Unity.LauncherEntry.get_for_desktop_id("shotwell.desktop");
    private static UnityProgressBar? visible_uniprobar;

    private double progress;
    private bool visible;

    public static UnityProgressBar get_instance() {
        if (visible_uniprobar == null) {
            visible_uniprobar = new UnityProgressBar();
        }

        return visible_uniprobar;
    }

    private UnityProgressBar() {
        progress = 0.0;
        visible = false;
    }

    ~UnityProgressBar () {
        reset_progress_bar();
    }
    
    public double get_progress () {
        return progress;
    }
    
    public void set_progress (double percent) {
        progress = percent;
        update_visibility();
    }

    private void update_visibility () {
        set_progress_bar(this, progress);
    }
    
    public bool get_visible () {
        return visible;
    }
    
    public void set_visible (bool visible) {
        this.visible = visible;

        if (!visible) {
            //if not visible and currently displayed, remove Unity progress bar
            reset_progress_bar();
        } else {
            //update_visibility if this progress bar wants to be drawn
            update_visibility();            
        }
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

#endif
