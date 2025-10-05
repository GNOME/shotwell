natural_collate_test = executable('natural-collate-test',
                                  ['NaturalCollate-Test.vala', 'NaturalCollate.vala'],
                                  dependencies : gio)

jfif_support_test = executable('jfif-support-test',
                               ['jfif/JfifSupport-Test.vala',
                                'jfif/PhotoFileSniffer.vala',
                                'jfif/PhotoFileAdapter.vala',
                                'jfif/JfifSupport.vala',
                                'jfif/GdkSupport.vala',
                                'jfif/KeyValueMap.vala',
                                'jfif/Dimensions.vala',
                                'jfif/string.vala',
                                'jfif/file.vala',
                                'jfif/util_core-stub.vala',
                                'jfif/ProgressMonitor-stub.vala',
                                'jfif/PhotoMetadata-stub.vala',
                                'jfif/PhotoFileFormat-jfifstub.vala',
                                'jfif/util_image-stub.vala'],
                               dependencies : [gio, gee, gtk, gexiv2, math],
                               c_args : ['-DTEST_DATA_DIR="@0@"'.format(meson.current_source_dir())]
                             )

regexp_replace_test = executable('regexp-replace-test',
                                 ['RegexpReplace.vala', 'DatabaseTable.vala'],
                                 dependencies: [gee, gio, sqlite])

test('natural-collate', natural_collate_test)
test('jfif-support', jfif_support_test)
test('regexp-replace', regexp_replace_test)
