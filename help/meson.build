install_man('shotwell.1')

find_program('itstool', required: true)

yelp_pages = [
    'edit-adjustments.page',
    'edit-crop.page',
    'edit-date-time.page',
    'edit-enhance.page',
    'edit-external.page',
    'edit-nondestructive.page',
    'edit-redeye.page',
    'edit-rotate.page',
    'edit-straighten.page',
    'edit-undo.page',
    'formats.page',
    'import-camera.page',
    'import-file.page',
    'import-memorycard.page',
    'index.page',
    'organize-event.page',
    'organize-flag.page',
    'organize-rating.page',
    'organize-remove.page',
    'organize-search.page',
    'organize-tag.page',
    'organize-title.page',
    'other-files.page',
    'other-missing.page',
    'other-multiple.page',
    'other-plugins.page',
    'privacy-policy.page',
    'raw.page',
    'running.page',
    'share-background.page',
    'share-export.page',
    'share-print.page',
    'share-send.page',
    'share-slideshow.page',
    'share-upload.page',
    'view-displaying.page',
    'view-information.page',
    'view-sidebar.page']

yelp_media = [
    'figures/Shotwell.svg',
    'figures/trash_process.png',
    'figures/crop_thirds.jpg',
    'figures/trash_process.svg']

gnome.yelp('shotwell',
           sources : yelp_pages,
           media : yelp_media,
           symlink_media : true)
