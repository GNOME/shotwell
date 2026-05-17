// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2016 Software Freedom Convervancy Inc.

public enum ContentLayout {
    STANDARD_SIZE,
    CUSTOM_SIZE,
    IMAGE_PER_PAGE
}

public class PrintSettings {
    public const int MIN_CONTENT_PPI = 72;    /* 72 ppi is the pixel resolution of a 14" VGA
                                                 display -- it's standard for historical reasons */
    public const int MAX_CONTENT_PPI = 1200;  /* 1200 ppi is appropriate for a 3600 dpi imagesetter
                                                 used to produce photographic plates for commercial
                                                 printing -- it's the highest pixel resolution
                                                 commonly used */
    private ContentLayout content_layout;
    private Measurement content_width;
    private Measurement content_height;
    private int content_ppi;
    private int image_per_page_selection;
    private int size_selection;
    private bool match_aspect_ratio;
    private bool print_titles;
    private string print_titles_font;

    public PrintSettings() {
        Config.Facade config = Config.Facade.get_instance();

        MeasurementUnit units = (MeasurementUnit) config.get_printing_content_units();
        
        content_width = Measurement(config.get_printing_content_width(), units);
        content_height = Measurement(config.get_printing_content_height(), units);
        size_selection = config.get_printing_size_selection();
        print("================> Size selection is %d\n", size_selection);
        content_layout = (ContentLayout) config.get_printing_content_layout();
        match_aspect_ratio = config.get_printing_match_aspect_ratio();
        print_titles = config.get_printing_print_titles();
        print_titles_font = config.get_printing_titles_font();
        image_per_page_selection = config.get_printing_images_per_page();
        content_ppi = config.get_printing_content_ppi();
        print("creating print settings %p\n", this);
    }

    ~PrintSettings() {
        print("Deleting print settings %p\n", this);
    }

    public void save() {
        Config.Facade config = Config.Facade.get_instance();

        print("=>>>>>>>>> Saving print settings\n");

        config.set_printing_content_units(content_width.unit);
        config.set_printing_content_width(content_width.value);
        config.set_printing_content_height(content_height.value);
        config.set_printing_size_selection(size_selection);
        config.set_printing_content_layout(content_layout);
        config.set_printing_match_aspect_ratio(match_aspect_ratio);
        config.set_printing_print_titles(print_titles);
        config.set_printing_titles_font(print_titles_font);
        config.set_printing_images_per_page(image_per_page_selection);
        config.set_printing_content_ppi(content_ppi);
    }


    public Measurement get_content_width() {
        switch (get_content_layout()) {
            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.IMAGE_PER_PAGE:
                print("Print manager: %p, Self: %p, sz: %p\n", PrintManager.get_instance(), this, PrintManager.get_instance().get_standard_sizes());
                var sel = get_size_selection();
                print("  %d %d:\n", sel, PrintManager.get_instance().get_standard_sizes().length);
                return (PrintManager.get_instance().get_standard_sizes()[
                    get_size_selection()]).width;

            case ContentLayout.CUSTOM_SIZE:
                return content_width;

            default:
                error("unknown ContentLayout enumeration value");
        }
    }

    public Measurement get_content_height() {
        switch (get_content_layout()) {
            case ContentLayout.STANDARD_SIZE:
            case ContentLayout.IMAGE_PER_PAGE:
                return (PrintManager.get_instance().get_standard_sizes()[
                    get_size_selection()]).height;

            case ContentLayout.CUSTOM_SIZE:
                return content_height;

            default:
                error("unknown ContentLayout enumeration value");
        }
    }

    public Measurement get_minimum_content_dimension() {
        return Measurement(0.5, MeasurementUnit.INCHES);
    }

    public Measurement get_maximum_content_dimension() {
        return Measurement(30, MeasurementUnit.INCHES);
    }

    public bool is_match_aspect_ratio_enabled() {
        return match_aspect_ratio;
    }

    public bool is_print_titles_enabled() {
        return print_titles;
    }

    public int get_content_ppi() {
        return content_ppi;
    }

    public int get_image_per_page_selection() {
        return image_per_page_selection;
    }

    public int get_size_selection() {
        return size_selection;
    }

    public ContentLayout get_content_layout() {
        return content_layout;
    }

    public void set_content_layout(ContentLayout content_layout) {
        this.content_layout = content_layout;
    }

    public void set_content_width(Measurement content_width) {
        this.content_width = content_width;
    }

    public void set_content_height(Measurement content_height) {
        this.content_height = content_height;
    }

    public void set_content_ppi(int content_ppi) {
        this.content_ppi = content_ppi;
    }

    public void set_image_per_page_selection(int image_per_page_selection) {
        this.image_per_page_selection = image_per_page_selection;
    }

    public void set_size_selection(int size_selection) {
        this.size_selection = size_selection;
    }

    public void set_match_aspect_ratio_enabled(bool enable_state) {
        this.match_aspect_ratio = enable_state;
    }

    public void set_print_titles_enabled(bool print_titles) {
        this.print_titles = print_titles;
    }

    public void set_print_titles_font(string fontname) {
        this.print_titles_font = fontname;
    }

    public string get_print_titles_font() {
        return this.print_titles_font;
    }
}

private enum PrintLayout {
    ENTIRE_PAGE,
    TWO_PER_PAGE,
    FOUR_PER_PAGE,
    SIX_PER_PAGE,
    EIGHT_PER_PAGE,
    SIXTEEN_PER_PAGE,
    THIRTY_TWO_PER_PAGE;
    
    public static PrintLayout[] get_all() {
        return {
            ENTIRE_PAGE,
            TWO_PER_PAGE,
            FOUR_PER_PAGE,
            SIX_PER_PAGE,
            EIGHT_PER_PAGE,
            SIXTEEN_PER_PAGE,
            THIRTY_TWO_PER_PAGE
        };
    }
    
    public int get_per_page() {
        int[] per_page = { 1, 2, 4, 6, 8, 16, 32 };
        
        return per_page[this];
    }
    
    public int get_x() {
        int[] x = { 1, 1, 2, 2, 2, 4, 4 };
        
        return x[this];
     }
    
    public int get_y() {
        int[] y = { 1, 2, 2, 3, 4, 4, 8 };
        
        return y[this];
    }
    
    public string to_string() {
        string[] labels = {
            _("Fill the entire page"),
            _("2 images per page"),
            _("4 images per page"),
            _("6 images per page"),
            _("8 images per page"),
            _("16 images per page"),
            _("32 images per page")
        };
        
        return labels[this];
    }
}
