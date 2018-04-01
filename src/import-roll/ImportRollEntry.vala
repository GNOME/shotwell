/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ImportRoll.SidebarEntry : Library.HideablePageEntry {
    private ImportID id;
    private string name;

    public SidebarEntry(ImportID id) {
        base();

        this.id = id;
        this.name = new DateTime.from_unix_local(id.id).format("%c");
    }
    
    public ImportID get_id() {
        return id;
    }
    
    public override string get_sidebar_name() {
        return this.name;
    }
    
    public override string? get_sidebar_icon() {
        return Resources.ICON_LAST_IMPORT;
    }
    
    protected override Page create_page() {
        return new LastImportPage.for_id(this.id);
    }
}

