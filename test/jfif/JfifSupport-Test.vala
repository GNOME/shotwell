// SPDX-License-Identifier: LGPLv2.1-or-later

[CCode (cname="TEST_DATA_DIR")]
extern const string TEST_DATA_DIR;

void add_jfif_sof_tests () {
    Test.add_func ("/unit/photos/jfif/is_sof", () => {
      Jpeg.Marker m = (Jpeg.Marker)0x8f;
      assert(! m.is_sof());
      m = (Jpeg.Marker)0xc0;
      assert(m.is_sof());
      m = (Jpeg.Marker)0xc4;
      assert(! m.is_sof());
      m = (Jpeg.Marker)0xe0;
      assert(! m.is_sof());
    });
}

void add_jfif_sniff_fast_tests () {
    Test.add_func ("/functional/photos/jfif/sniff_fast", () => {
            File f = File.new_for_path(TEST_DATA_DIR + "/shotwell-street.jpg");
            JfifSniffer s = new JfifSniffer(f, PhotoFileSniffer.Options.NO_MD5);
            bool is_corrupted = false;
            try {
                DetectedPhotoInformation detected = s.sniff(out is_corrupted);
                assert(!is_corrupted);
                assert(detected.channels == 3);
                assert(detected.bits_per_channel == 8);
                assert(detected.format_name == "jpeg");
                assert(detected.image_dim.width == 360);
                assert(detected.image_dim.height == 236);
                } catch (Error err) {
                assert_not_reached();
            }
    });
}

void add_svg_sniff_tests () {
    Test.add_func ("/functional/photos/svg/sniff", () => {
            File f = File.new_for_path(TEST_DATA_DIR + "/shotwell-street.svg");
            SvgSniffer s = new SvgSniffer(f, PhotoFileSniffer.Options.NO_MD5);
            bool is_corrupted = false;
            try {
                DetectedPhotoInformation detected = s.sniff(out is_corrupted);
                assert(!is_corrupted);
                assert(detected != null);
                assert(detected.file_format == PhotoFileFormat.SVG);
                assert(detected.channels == 4);
                assert(detected.bits_per_channel == 8);
                assert(detected.format_name == "svg");
                assert(detected.image_dim.width == 200);
                assert(detected.image_dim.height == 100);
                } catch (Error err) {
                assert_not_reached();
            }
    });

    // A non-SVG file must not be claimed by the SVG sniffer.
    Test.add_func ("/functional/photos/svg/sniff_negative", () => {
            File f = File.new_for_path(TEST_DATA_DIR + "/shotwell-street.jpg");
            SvgSniffer s = new SvgSniffer(f, PhotoFileSniffer.Options.NO_MD5);
            bool is_corrupted = false;
            try {
                DetectedPhotoInformation detected = s.sniff(out is_corrupted);
                assert(detected == null);
                } catch (Error err) {
                assert_not_reached();
            }
    });
}

void main (string[] args) {
    Test.init (ref args);
    add_jfif_sof_tests();
    add_jfif_sniff_fast_tests();
    add_svg_sniff_tests();
    Test.run();
}

