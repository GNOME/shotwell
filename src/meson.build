subdir('plugins')

sw_graphics_processor = static_library('shotwell-graphics-processor',
               ['ColorTransformation.vala',
                'util/KeyValueMap.vala',
                '_transformation.c'],
               vala_header : 'shotwell-graphics-processor.h',
               vala_vapi : 'shotwell-graphics-processor.vapi',
               dependencies : [gio, gee, gdk_pixbuf],
               include_directories : config_incdir,
               c_args : '-DG_DISABLE_CAST_CHECKS',
               vala_args : '--disable-assert',
               install : false)

processor = executable('shotwell-graphics-processor',
                       ['graphics-processor.vala'],
                       dependencies: [gio, gee, gdk_pixbuf],
                       link_with: sw_graphics_processor)

shotwell_libs = [sw_graphics_processor]
executable('shotwell-authenticator',
  [
    'authenticator.vala'
  ],
  dependencies: [gio],
  include_directories: config_incdir,
  install: true,
  install_dir : join_paths(get_option('libexecdir'), 'shotwell')
)


face_sources = (['faces/FacesBranch.vala',
                     'faces/FacePage.vala',
                     'faces/FaceShape.vala',
                     'faces/FaceDetect.vala',
                     'faces/Faces.vala',
                     'faces/FacesTool.vala'])

shotwell_deps = [gio, gee, sqlite, gtk, sqlite, posix, gphoto2,
                 gstreamer_pbu, gudev, gexiv2, gmodule,
                 libraw, libexif, sw_plugin, webpdemux, webp, version, pangocairo,
                 portal]

subdir('metadata')
subdir('publishing')
subdir('video-support')
subdir('widgets')

executable(
    'shotwell',
    [
        'unit/Unit.vala',
        'util/Util.vala',
        'util/file.vala',
        'util/image.vala',
        'util/misc.vala',
        'util/string.vala',
        'util/system.vala',
        'util/ui.vala',
        'threads/Threads.vala',
        'threads/Workers.vala',
        'threads/BackgroundJob.vala',
        'threads/Semaphore.vala',
        'db/Db.vala',
        'db/DatabaseTable.vala',
        'db/PhotoTable.vala',
        'db/EventTable.vala',
        'db/FaceLocationTable.vala',
        'db/FaceTable.vala',
        'db/TagTable.vala',
        'db/TombstoneTable.vala',
        'db/VideoTable.vala',
        'db/VersionTable.vala',
        'db/SavedSearchDBTable.vala',
        'editing_tools/AdjustTool.vala',
        'editing_tools/EditingTools.vala',
        'editing_tools/EditingTool.vala',
        'editing_tools/CropTool.vala',
        'editing_tools/PhotoCanvas.vala',
        'editing_tools/RedeyeTool.vala',
        'editing_tools/StraightenTool.vala',
        'editing_tools/EditingToolWindow.vala',
        'editing_tools/RGBHistogramManipulator.vala',
        'faces/Face.vala',
        'faces/FaceLocation.vala',
        'slideshow/Slideshow.vala',
        'slideshow/TransitionEffects.vala',
        'photos/Photos.vala',
        'photos/PhotoFileAdapter.vala',
        'photos/PhotoFileFormat.vala',
        'photos/PhotoFileSniffer.vala',
        'photos/PhotoMetadata.vala',
        'photos/GRaw.vala',
        'photos/GdkSupport.vala',
        'photos/GifSupport.vala',
        'photos/JfifSupport.vala',
        'photos/BmpSupport.vala',
        'photos/RawSupport.vala',
        'photos/PngSupport.vala',
        'photos/TiffSupport.vala',
        'photos/WebPSupport.vala',
        'photos/AvifSupport.vala',
        'photos/HeifSupport.vala',
        'photos/JpegXLSupport.vala',
        'plugins/Plugins.vala',
        'plugins/StandardHostInterface.vala',
        'plugins/ManifestWidget.vala',
        'publishing/Publishing.vala',
        'publishing/PublishingUI.vala',
        'publishing/PublishingPluginHost.vala',
        'publishing/APIGlue.vala',
        'library/BackgroundProgressBar.vala',
        'library/Library.vala',
        'library/LibraryWindow.vala',
        'library/LibraryBranch.vala',
        'library/TrashSidebarEntry.vala',
        'library/OfflineSidebarEntry.vala',
        'library/FlaggedSidebarEntry.vala',
        'library/LastImportSidebarEntry.vala',
        'library/ImportQueueSidebarEntry.vala',        
        'library/FlaggedPage.vala',
        'library/ImportQueuePage.vala',
        'library/LastImportPage.vala',
        'library/OfflinePage.vala',
        'library/TrashPage.vala',
        'direct/Direct.vala',
        'direct/DirectWindow.vala',
        'direct/DirectPhoto.vala',
        'direct/DirectPhotoPage.vala',
        'direct/DirectView.vala',
        'core/Core.vala',
        'core/DataCollection.vala',
        'core/DataSet.vala',
        'core/util.vala',
        'core/SourceCollection.vala',
        'core/SourceHoldingTank.vala',
        'core/DatabaseSourceCollection.vala',
        'core/ContainerSourceCollection.vala',
        'core/ViewCollection.vala',
        'core/DataObject.vala',
        'core/Alteration.vala',
        'core/DataSource.vala',
        'core/DataSourceTypes.vala',
        'core/DataView.vala',
        'core/DataViewTypes.vala',
        'core/Tracker.vala',
        'core/SourceInterfaces.vala',
        'sidebar/Sidebar.vala',
        'sidebar/Branch.vala',
        'sidebar/Entry.vala',
        'sidebar/Tree.vala',
        'sidebar/common.vala',
        'events/Events.vala',
        'events/EventsBranch.vala',
        'events/EventsDirectoryPage.vala',
        'events/EventPage.vala',
        'events/EventDirectoryItem.vala',
        'tags/Tags.vala',
        'tags/TagsBranch.vala',
        'tags/TagPage.vala',
        'tags/HierarchicalTagIndex.vala',
        'tags/HierarchicalTagUtilities.vala',
        'camera/Camera.vala',
        'camera/CameraBranch.vala',
        'camera/CameraTable.vala',
        'camera/DiscoveredCamera.vala',
        'camera/GPhoto.vala',
        'camera/ImportPage.vala',
        'searches/Searches.vala',
        'searches/SearchesBranch.vala',
        'searches/SearchBoolean.vala',
        'searches/SavedSearchPage.vala',
        'searches/SavedSearchDialog.vala',
        'config/Config.vala',
        'config/ConfigurationInterfaces.vala',
        'config/GSettingsEngine.vala',
        'data_imports/DataImports.vala',
        'data_imports/DataImportsPluginHost.vala',
        'data_imports/DataImportsUI.vala',
        'data_imports/DataImportJob.vala',
        'data_imports/DataImportSource.vala',        
        'folders/Folders.vala',
        'folders/FoldersBranch.vala',
        'folders/FoldersPage.vala',
        'import-roll/ImportRollBranch.vala',
        'import-roll/ImportRollEntry.vala',        
        'main.vala',
        'AppWindow.vala',
        'FullscreenWindow.vala',
        'PageWindow.vala',
        'CollectionPage.vala',
        'NaturalCollate.vala',
        'Thumbnail.vala',
        'ThumbnailCache.vala',
        'CheckerboardItem.vala',
        'CheckerboardItemText.vala',
        'CheckerboardLayout.vala',
        'Page.vala',
        'SinglePhotoPage.vala',
        'CheckerboardPage.vala',
        'PageMessagePane.vala',
        'SortedList.vala',
        'Dimensions.vala',
        'Box.vala',
        'Photo.vala',
        'Orientation.vala',
        'BatchImport.vala',
        'Dialogs.vala',
        'Resources.vala',
        'Debug.vala',
        'Properties.vala',
        'Event.vala',
        'International.vala',
        'AppDirs.vala',
        'PixbufCache.vala',
        'CommandManager.vala',
        'Commands.vala',
        'SlideshowPage.vala',
        'LibraryFiles.vala',
        'Printing.vala',
        'Tag.vala',
        'Screensaver.vala',
        'Exporter.vala',
        'DirectoryMonitor.vala',
        'LibraryMonitor.vala',
        'Tombstone.vala',
        'MetadataWriter.vala',
        'Application.vala',
        'TimedQueue.vala',
        'MediaPage.vala',
        'MediaDataRepresentation.vala',
        'DesktopIntegration.vala',
        'LibraryPhotoPage.vala',
        'ZoomBuffer.vala',
        'EditingHostPage.vala',
        'MediaInterfaces.vala',
        'MediaMonitor.vala',
        'PhotoMonitor.vala',
        'VideoMonitor.vala',
        'SearchFilter.vala',
        'SavedSearchPopover.vala',
        'MediaViewTracker.vala',
        'Upgrades.vala',
        'dialogs/AdjustDateTimeDialog.vala',
        'dialogs/EntryMultiCompletion.vala',
        'dialogs/ExportDialog.vala',
        'dialogs/MultiTextEntryDialog.vala',
        'dialogs/Preferences.vala',
        'dialogs/ProgressDialog.vala',
        'dialogs/SetBackgroundSlideshow.vala',
        'dialogs/SetBackground.vala',
        'dialogs/TextEntry.vala',
        'dialogs/WelcomeDialog.vala',
        'Profiles.vala',
        'ProfileBrowser.vala',
        '.unitize/_UnitInternals.vala',
        '.unitize/_UtilInternals.vala',
        '.unitize/_ThreadsInternals.vala',
        '.unitize/_DbInternals.vala',
        '.unitize/_EditingToolsInternals.vala',
        '.unitize/_PluginsInternals.vala',
        '.unitize/_SlideshowInternals.vala',
        '.unitize/_PhotosInternals.vala',
        '.unitize/_PublishingInternals.vala',
        '.unitize/_LibraryInternals.vala',
        '.unitize/_DirectInternals.vala',
        '.unitize/_CoreInternals.vala',
        '.unitize/_SidebarInternals.vala',
        '.unitize/_EventsInternals.vala',
        '.unitize/_TagsInternals.vala',
        '.unitize/_CameraInternals.vala',
        '.unitize/_SearchesInternals.vala',
        '.unitize/_ConfigInternals.vala',
        '.unitize/_DataImportsInternals.vala',
        '.unitize/_FoldersInternals.vala',
        '.unitize/_Library_unitize_entry.vala',
        '.unitize/_Direct_unitize_entry.vala',
        'video-support/VideoReader.vala',
        'video-support/VideoImportParams.vala',
        'video-support/Video.vala',
        'video-support/VideoSourceCollection.vala',
        'video-support/VideoMetadata.vala'
    ] + shotwell_resources + face_sources,
    include_directories : vapi_incdir,
    dependencies : [
        shotwell_deps,
        sw_publishing_gui,
        metadata,
        metadata_handling,
        widgets
    ],
    vala_args : [
        '--pkg', 'libgphoto2',
        '--pkg', 'libraw',
        '--pkg', 'libexif',
        '--pkg', 'version',
        '--gresources',
        join_paths(meson.project_source_root(), 'data',
        'org.gnome.Shotwell.gresource.xml')
    ],
    link_with: [
        sw_graphics_processor,
    ],
    install : true
)
