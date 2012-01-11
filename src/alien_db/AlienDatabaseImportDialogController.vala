/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace AlienDb {

public class AlienDatabaseImportDialogController {
    private AlienDatabaseImportDialog dialog;
    
    public AlienDatabaseImportDialogController(string title, AlienDatabaseDriver driver,
        BatchImport.ImportReporter? reporter = null) {
        if (reporter == null)
            reporter = alien_import_reporter;
            
        Gtk.Builder builder = AppWindow.create_builder();
        dialog = builder.get_object("alien-db-import_dialog") as AlienDatabaseImportDialog;
        dialog.set_builder(builder);
        dialog.setup(title, driver, reporter);
    }
    
    public void execute() {
        dialog.execute();
    }
}

}

