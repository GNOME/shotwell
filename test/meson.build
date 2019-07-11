external_helper_test_executable = executable(
    'external_helper',
    files([
        'ExternalHelperTestExecutable.vala',
    ]),
    dependencies : gio
)

external_helper_test = executable(
    'external-helper-test',
    files([
        'ExternalHelperTest.vala',
        'ExternalHelper.vala'
    ]),
    dependencies: gio,
    c_args : [ '-DEXTERNAL_HELPER_EXECUTABLE="@0@"'.format(external_helper_test_executable.full_path()) ]
)
natural_collate_test = executable('natural-collate-test',
                                  ['NaturalCollate-Test.vala', 'NaturalCollate.vala'],
                                  dependencies : gio)

test('natural-collate', natural_collate_test)
test('external-helper-test', external_helper_test)
