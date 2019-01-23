/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace PublishingUI {

public class SuccessPane : StaticMessagePane {
    public SuccessPane(Spit.Publishing.Publisher.MediaType published_media, int num_uploaded = 1) {
        string? message_string = null;

        // Here, we check whether more than one item is being uploaded, and if so, display
        // an alternate message.
        if (published_media == Spit.Publishing.Publisher.MediaType.VIDEO) {
            message_string = ngettext ("The selected video was successfully published.",
                                       "The selected videos were successfully published.",
                                       num_uploaded);
        }
        else if (published_media == Spit.Publishing.Publisher.MediaType.PHOTO) {
            message_string = ngettext ("The selected photo was successfully published.",
                                       "The selected photos were successfully published.",
                                       num_uploaded);
        }
        else if (published_media == (Spit.Publishing.Publisher.MediaType.PHOTO
                                     | Spit.Publishing.Publisher.MediaType.VIDEO)) {
            message_string = _("The selected photos/videos were successfully published.");
        }
        else {
            assert_not_reached ();
        }

        base(message_string);
    }
}
}


