/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

namespace FacebookConnector {

public class Capabilities : ServiceCapabilities {
    public override string get_name() {
        return "Facebook";
    }
    
    public override Spit.Publishing.Publisher.MediaType get_supported_media() {
        return Spit.Publishing.Publisher.MediaType.PHOTO | Spit.Publishing.Publisher.MediaType.VIDEO;
    }
    
    public override ServiceInteractor factory(PublishingDialog host) {
        return Publishing.Glue.GlueFactory.get_instance().create_publisher("facebook");
    }
}

}

