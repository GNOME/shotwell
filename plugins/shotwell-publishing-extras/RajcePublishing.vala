/* Copyright 2014 rajce.net
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class RajceService : Object, Spit.Pluggable, Spit.Publishing.Service
{
    private const string ICON_FILENAME = "rajce.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;
    
    public RajceService(GLib.File resource_directory)
	{
        if (icon_pixbuf_set == null)
            icon_pixbuf_set =
                Resources.load_from_resource(Resources.RESOURCE_PATH + "/" +
                        ICON_FILENAME);
    }

    public int get_pluggable_interface(int min_host_interface, int max_host_interface)
	{
        return Spit.negotiate_interfaces(min_host_interface, max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }
    
    public unowned string get_id()
	{
        return "org.yorba.shotwell.publishing.rajce";
    }
    
    public unowned string get_pluggable_name()
	{
        return "Rajce";
    }
    
    public void get_info(ref Spit.PluggableInfo info)
	{
        info.authors = "rajce.net developers";
        info.copyright = _("Copyright © 2013 rajce.net");
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        info.website_name = Resources.WEBSITE_NAME;
        info.website_url = Resources.WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = Resources.LICENSE;
        info.icons = icon_pixbuf_set;
    }
    
    public Spit.Publishing.Publisher create_publisher(Spit.Publishing.PluginHost host)
	{
        return new Publishing.Rajce.RajcePublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media()
	{
        return( Spit.Publishing.Publisher.MediaType.PHOTO /*| Spit.Publishing.Publisher.MediaType.VIDEO*/ );
    }
    
    public void activation(bool enabled) {}
}

namespace Publishing.Rajce
{

public class RajcePublisher : Spit.Publishing.Publisher, GLib.Object
{
    private Spit.Publishing.PluginHost host = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private Spit.Publishing.Service service = null;
    private bool running = false;
    private Session session;
//    private string username = "";
//    private string token = "";
//    private int last_photo_size = -1;
//    private bool hide_album = false;
//    private bool show_album = true;
//    private bool remember = false;
//    private bool strip_metadata = false;
    private Album[] albums = null;
    private PublishingParameters parameters = null;
    private Spit.Publishing.Publisher.MediaType media_type = Spit.Publishing.Publisher.MediaType.NONE;

    public RajcePublisher(Spit.Publishing.Service service, Spit.Publishing.PluginHost host)
	{
        debug("RajcePublisher created.");
        this.service = service;
        this.host = host;
        this.session = new Session();
        
        foreach(Spit.Publishing.Publishable p in host.get_publishables())
            media_type |= p.get_media_type();
    }
    
    private string get_rajce_url()
	{
        return "http://www.rajce.idnes.cz/liveAPI/index.php";
    }

	// Publisher interface implementation
	
    public Spit.Publishing.Service get_service() { return service; }
    public Spit.Publishing.PluginHost get_host() { return host; }
    public bool is_running() { return running; }
    
    public void start()
	{
        if (is_running())
            return;
        
        debug("RajcePublisher: start");
        running = true;
        
        if (session.is_authenticated())
		{
            debug("RajcePublisher: session is authenticated.");
            do_fetch_albums();
        }
		else
		{
            debug("RajcePublisher: session is not authenticated.");
            string? persistent_username = get_username();
            string? persistent_token = get_token();
            bool? persistent_remember = get_remember();
            if (persistent_username != null && persistent_token != null)
                do_network_login(persistent_username, persistent_token, persistent_remember );
            else
                do_show_authentication_pane();
        }
    }
    
    public void stop()
	{
        debug("RajcePublisher: stop");
        running = false;
    }

	// persistent data

    public string? get_url() { return get_rajce_url(); }
    public string? get_username() { return host.get_config_string("username", null); }
    private void set_username(string username) { host.set_config_string("username", username); }
    public string? get_token() { return host.get_config_string("token", null); }
    private void set_token(string? token) { host.set_config_string("token", token); }
//    public int get_last_photo_size() { return host.get_config_int("last-photo-size", -1); }
//    private void set_last_photo_size(int last_photo_size) { host.set_config_int("last-photo-size", last_photo_size); }
    public bool get_remember() { return host.get_config_bool("remember", false); }
    private void set_remember(bool remember) { host.set_config_bool("remember", remember); }
    public bool get_hide_album() { return host.get_config_bool("hide-album", false); }
    public void set_hide_album(bool hide_album) { host.set_config_bool("hide-album", hide_album); }
    public bool get_show_album() { return host.get_config_bool("show-album", true); }
    public void set_show_album(bool show_album) { host.set_config_bool("show-album", show_album); }
//    public bool get_strip_metadata() { return host.get_config_bool("strip-metadata", false); }
//    private void set_strip_metadata(bool strip_metadata) { host.set_config_bool("strip-metadata", strip_metadata); }

    // Actions and events
    
    /**
     * Action that shows the authentication pane.
     */
    private void do_show_authentication_pane(AuthenticationPane.Mode mode = AuthenticationPane.Mode.INTRO)
	{
        debug("ACTION: installing authentication pane");

        host.set_service_locked(false);
        AuthenticationPane authentication_pane = new AuthenticationPane(this, mode);
        authentication_pane.login.connect(on_authentication_pane_login_clicked);
        host.install_dialog_pane(authentication_pane, Spit.Publishing.PluginHost.ButtonMode.CLOSE);
        host.set_dialog_default_widget(authentication_pane.get_default_widget());
    }

    /**
     * Event triggered when the login button in the authentication panel is clicked.
     */
    private void on_authentication_pane_login_clicked( string username, string token, bool remember )
	{
        debug("EVENT: on_authentication_pane_login_clicked");
        if (!running)
            return;
        do_network_login(username, token, remember);
    }
    
    /**
     * Action to perform a network login to a Rajce service.
     */
    private void do_network_login(string username, string token, bool remember)
	{
        debug("ACTION: logging in");
        host.set_service_locked(true);
        host.install_login_wait_pane();
        set_remember( remember );
        set_username( username );
        set_token( remember ? token : null );
        SessionLoginTransaction login_trans = new SessionLoginTransaction(session, get_url(), username, token);
        login_trans.network_error.connect(on_login_network_error);
        login_trans.completed.connect(on_login_network_complete);
        try
		{
            login_trans.execute();
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: do_network_login");
            do_show_error(err);
        }
    }
    
    /**
     * Event triggered when the network login action is complete and successful.
     */
    private void on_login_network_complete(Publishing.RESTSupport.Transaction txn)
	{
        debug("EVENT: on_login_network_complete");
        txn.completed.disconnect(on_login_network_complete);
        txn.network_error.disconnect(on_login_network_error);
        
        try
		{
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string( txn.get_response(), Transaction.validate_xml);
            Xml.Node* response = doc.get_root_node();
            Xml.Node* sessionToken = doc.get_named_child( response, "sessionToken" );
            Xml.Node* maxWidth = doc.get_named_child( response, "maxWidth" );
            Xml.Node* maxHeight = doc.get_named_child( response, "maxHeight" );
            Xml.Node* quality = doc.get_named_child( response, "quality" );
            Xml.Node* nick = doc.get_named_child( response, "nick" );
			int maxW = int.parse( maxWidth->get_content() );
			int maxH = int.parse( maxHeight->get_content() );
			if( maxW > maxH )
			{
				maxH = maxW;
			}
			session.authenticate( sessionToken->get_content(), nick->get_content(), 0, maxH, int.parse( quality->get_content() ) ); 
        }
		catch (Spit.Publishing.PublishingError err)
		{
			int code_int = int.parse(err.message);
			if (code_int == 999)
			{
                debug("ERROR: on_login_network_complete, code 999");
                do_show_authentication_pane(AuthenticationPane.Mode.FAILED_RETRY_USER);
            }
			else
			{
                debug("ERROR: on_login_network_complete");
                do_show_error(err);
            }
            return;
        }
        do_fetch_albums();
    }
    
    /**
     * Event triggered when a network login action fails due to a network error.
     */
    private void on_login_network_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_login_network_error");
        bad_txn.completed.disconnect(on_login_network_complete);
        bad_txn.network_error.disconnect(on_login_network_error);
        do_show_authentication_pane(AuthenticationPane.Mode.FAILED_RETRY_USER);
    }

    /**
     * Action that fetches all user albums from the Rajce.
     */
    private void do_fetch_albums()
	{
        debug("ACTION: fetching albums");
        host.set_service_locked(true);
        host.install_account_fetch_wait_pane();

        GetAlbumsTransaction get_albums_trans = new GetAlbumsTransaction(session, get_url() );
        get_albums_trans.network_error.connect(on_albums_fetch_error);
        get_albums_trans.completed.connect(on_albums_fetch_complete);
        
        try
		{
            get_albums_trans.execute();
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: do_fetch_albums");
            do_show_error(err);
        }
    }

    /**
     * Event triggered when the fetch albums action completes successfully.
     */
    private void on_albums_fetch_complete(Publishing.RESTSupport.Transaction txn)
	{
        debug("EVENT: on_albums_fetch_complete");
        txn.completed.disconnect(on_albums_fetch_complete);
        txn.network_error.disconnect(on_albums_fetch_error);
        debug("RajcePlugin: list of albums: %s", txn.get_response());
        if (albums != null)
		{
            albums = null;
        }
		Gee.ArrayList<Album> list = new Gee.ArrayList<Album>();
        try
		{
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string( txn.get_response(), Transaction.validate_xml);
            Xml.Node* response = doc.get_root_node();
            Xml.Node* sessionToken = doc.get_named_child( response, "sessionToken" );
            Xml.Node* nodealbums = doc.get_named_child( response, "albums" );
			for( Xml.Node* album = nodealbums->children; album != null; album = album->next )
			{
				int id = int.parse( album->get_prop("id") );
		        string albumName = doc.get_named_child( album, "albumName" )->get_content();
		        string url = doc.get_named_child( album, "url" )->get_content();
		        string thumbUrl = doc.get_named_child( album, "thumbUrl" )->get_content();
		        string createDate = doc.get_named_child( album, "createDate" )->get_content();
		        string updateDate = doc.get_named_child( album, "updateDate" )->get_content();
		        bool hidden = ( int.parse( doc.get_named_child( album, "hidden" )->get_content() ) > 0 ? true : false );
		        bool secure = ( int.parse( doc.get_named_child( album, "secure" )->get_content() ) > 0 ? true : false );
		        int photoCount = int.parse( doc.get_named_child( album, "photoCount" )->get_content() );
				list.insert( 0, new Album( id, albumName, url, thumbUrl, createDate, updateDate, hidden, secure, photoCount ) ); 
			}
			list.sort( Album.compare_albums );
			albums = list.to_array();
			session.set_usertoken( sessionToken->get_content() );
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: on_albums_fetch_complete");
            do_show_error(err);
            return;
        }
        do_show_publishing_options_pane();
    }
    
    /**
     * Event triggered when the fetch albums transaction fails due to a network error.
     */
    private void on_albums_fetch_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_albums_fetch_error");
        bad_txn.completed.disconnect(on_albums_fetch_complete);
        bad_txn.network_error.disconnect(on_albums_fetch_error);
        on_network_error(bad_txn, err);
    }
    
    /**
     * Action that shows the publishing options pane.
     */
    private void do_show_publishing_options_pane()
	{
        debug("ACTION: installing publishing options pane");
        host.set_service_locked(false);
        PublishingOptionsPane opts_pane = new PublishingOptionsPane( this, session.get_username(), albums );
        opts_pane.logout.connect(on_publishing_options_pane_logout_clicked);
        opts_pane.publish.connect(on_publishing_options_pane_publish_clicked);
        host.install_dialog_pane(opts_pane, Spit.Publishing.PluginHost.ButtonMode.CLOSE);
        host.set_dialog_default_widget(opts_pane.get_default_widget());
    }
    
    /**
     * Event triggered when the user clicks logout in the publishing options pane.
     */
    private void on_publishing_options_pane_logout_clicked()
	{
        debug("EVENT: on_publishing_options_pane_logout_clicked");
        session.deauthenticate();
        do_show_authentication_pane( AuthenticationPane.Mode.INTRO );
    }
  
    /**
     * Event triggered when the user clicks publish in the publishing options pane.
     *
     * @param parameters the publishing parameters
     */
    private void on_publishing_options_pane_publish_clicked( PublishingParameters parameters )
	{
        debug("EVENT: on_publishing_options_pane_publish_clicked");
        this.parameters = parameters;
        do_begin_upload();
    }
  
    /**
     * Begin upload action: open existing album or create a new one
     */
    private void do_begin_upload()
	{
		host.set_service_locked(true);
		if( parameters.album_id == 0 )
		{
			// new album
		    debug("ACTION: closing album");
			CreateAlbumTransaction create_album_trans = new CreateAlbumTransaction(session, get_url(), parameters.album_name, this.parameters.album_hidden );
		    create_album_trans.network_error.connect(on_create_album_error);
		    create_album_trans.completed.connect(on_create_album_complete);
		    try
			{
		        create_album_trans.execute();
		    }
			catch (Spit.Publishing.PublishingError err)
			{
		        debug("ERROR: create album");
		        do_show_error(err);
		    }
		}
		else
		{
			// existing album
		    debug("ACTION: opening album");
			OpenAlbumTransaction open_album_trans = new OpenAlbumTransaction(session, get_url(), parameters.album_id );
		    open_album_trans.network_error.connect(on_open_album_error);
		    open_album_trans.completed.connect(on_open_album_complete);
		    try
			{
		        open_album_trans.execute();
		    }
			catch (Spit.Publishing.PublishingError err)
			{
		        debug("ERROR: open album");
		        do_show_error(err);
		    }
		}
	}

    /**
     * Event triggered when the create album completes successfully.
     */
    private void on_create_album_complete( Publishing.RESTSupport.Transaction txn)
	{
        debug("EVENT: on_create_album_complete");
        txn.completed.disconnect(on_create_album_complete);
        txn.network_error.disconnect(on_create_album_error);
        debug("RajcePlugin: create album: %s", txn.get_response());
        try
		{
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string( txn.get_response(), Transaction.validate_xml);
            Xml.Node* response = doc.get_root_node();
            string sessionToken = doc.get_named_child( response, "sessionToken" )->get_content();
            string albumToken = doc.get_named_child( response, "albumToken" )->get_content();
	        parameters.album_id = int.parse( doc.get_named_child( response, "albumID" )->get_content() );
			session.set_usertoken( sessionToken );
			session.set_albumtoken( albumToken );
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: on_create_album_complete");
            do_show_error(err);
            return;
        }
        do_upload_photos();
    }
    
    /**
     * Event triggered when the create album transaction fails due to a network error.
     */
    private void on_create_album_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_create_album_error");
        bad_txn.completed.disconnect(on_create_album_complete);
        bad_txn.network_error.disconnect(on_create_album_error);
        on_network_error(bad_txn, err);
    }

    /**
     * Event triggered when the open album completes successfully.
     */
    private void on_open_album_complete(Publishing.RESTSupport.Transaction txn)
	{
        debug("EVENT: on_open_album_complete");
        txn.completed.disconnect(on_open_album_complete);
        txn.network_error.disconnect(on_open_album_error);
        debug("RajcePlugin: open album: %s", txn.get_response());
        try
		{
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string( txn.get_response(), Transaction.validate_xml);
            Xml.Node* response = doc.get_root_node();
            string sessionToken = doc.get_named_child( response, "sessionToken" )->get_content();
            string albumToken = doc.get_named_child( response, "albumToken" )->get_content();
			session.set_usertoken( sessionToken );
			session.set_albumtoken( albumToken );
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: on_open_album_complete");
            do_show_error(err);
            return;
        }
        do_upload_photos();
    }
    
    /**
     * Event triggered when the open album transaction fails due to a network error.
     */
    private void on_open_album_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_open_album_error");
        bad_txn.completed.disconnect(on_open_album_complete);
        bad_txn.network_error.disconnect(on_open_album_error);
        on_network_error(bad_txn, err);
    }

    /**
     * Upload photos: the key part of the plugin
     */
    private void do_upload_photos()
	{
        debug("ACTION: uploading photos");
        progress_reporter = host.serialize_publishables( session.get_maxsize() );
        Spit.Publishing.Publishable[] publishables = host.get_publishables();
        
        Uploader uploader = new Uploader( session, get_url(), publishables, parameters );
        uploader.upload_complete.connect( on_upload_photos_complete );
        uploader.upload_error.connect( on_upload_photos_error );
        uploader.upload( on_upload_photos_status_updated );
    }
    
    /**
     * Event triggered when the batch uploader reports that at least one of the
     * network transactions encapsulating uploads has completed successfully
     */
    private void on_upload_photos_complete(Publishing.RESTSupport.BatchUploader uploader, int num_published)
	{
        debug("EVENT: on_upload_photos_complete");
        uploader.upload_complete.disconnect(on_upload_photos_complete);
        uploader.upload_error.disconnect(on_upload_photos_error);
        
        // TODO: should a message be displayed to the user if num_published is zero?
		do_end_upload();
    }
    
    /**
     * Event triggered when the batch uploader reports that at least one of the
     * network transactions encapsulating uploads has caused a network error
     */
    private void on_upload_photos_error( Publishing.RESTSupport.BatchUploader uploader, Spit.Publishing.PublishingError err)
	{
        debug("EVENT: on_upload_photos_error");
        uploader.upload_complete.disconnect(on_upload_photos_complete);
        uploader.upload_error.disconnect(on_upload_photos_error);
        do_show_error(err);
    }
    
    /**
     * Event triggered when upload progresses and the status needs to be updated.
     */
    private void on_upload_photos_status_updated(int file_number, double completed_fraction)
	{
        if( is_running() )
		{
		    debug("EVENT: uploader reports upload %.2f percent complete.", 100.0 * completed_fraction);
		    assert(progress_reporter != null);
		    progress_reporter(file_number, completed_fraction);
		}
    }

    private void do_end_upload()
	{
		if( get_show_album() )
		{
			do_get_album_url();
		}
		else
		{
			do_close_album();
		}
	}
	
	/**
     * End upload action: get album url
     */
    private void do_get_album_url()
	{
        debug("ACTION: getting album URL");
        host.set_service_locked(true);
		GetAlbumUrlTransaction get_album_url_trans = new GetAlbumUrlTransaction(session, get_url() );
	    get_album_url_trans.network_error.connect(on_get_album_url_error);
	    get_album_url_trans.completed.connect(on_get_album_url_complete);
	    try
		{
	        get_album_url_trans.execute();
	    }
		catch (Spit.Publishing.PublishingError err)
		{
	        debug("ERROR: close album");
	        do_show_error(err);
	    }
	}

    /**
     * Event triggered when the get album url completes successfully.
     */
    private void on_get_album_url_complete(Publishing.RESTSupport.Transaction txn)
	{
        debug("EVENT: on_get_album_url_complete");
        txn.completed.disconnect(on_get_album_url_complete);
        txn.network_error.disconnect(on_get_album_url_error);
        debug("RajcePlugin: get album url: %s", txn.get_response());
        try
		{
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string( txn.get_response(), Transaction.validate_xml);
            Xml.Node* response = doc.get_root_node();
            string sessionToken = doc.get_named_child( response, "sessionToken" )->get_content();
            string url = doc.get_named_child( response, "url" )->get_content();
			session.set_usertoken( sessionToken );
			session.set_albumticket( url );
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: on_get_album_url_complete");
		// ignore this error
//            do_show_error(err);
//            return;
        }
        do_close_album();
    }
    
    /**
     * Event triggered when the get album url transaction fails due to a network error.
     */
    private void on_get_album_url_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_get_album_url_error");
        bad_txn.completed.disconnect(on_get_album_url_complete);
        bad_txn.network_error.disconnect(on_get_album_url_error);
		// ignore this error
//        on_network_error(bad_txn, err);
        do_close_album();
    }


    /**
     * End upload action: close album
     */
    private void do_close_album()
	{
        debug("ACTION: closing album");
        host.set_service_locked(true);
		CloseAlbumTransaction close_album_trans = new CloseAlbumTransaction(session, get_url() );
	    close_album_trans.network_error.connect(on_close_album_error);
	    close_album_trans.completed.connect(on_close_album_complete);
	    try
		{
	        close_album_trans.execute();
	    }
		catch (Spit.Publishing.PublishingError err)
		{
	        debug("ERROR: close album");
	        do_show_error(err);
	    }
	}

    /**
     * Event triggered when the close album completes successfully.
     */
    private void on_close_album_complete(Publishing.RESTSupport.Transaction txn)
	{
        debug("EVENT: on_close_album_complete");
        txn.completed.disconnect(on_close_album_complete);
        txn.network_error.disconnect(on_close_album_error);
        debug("RajcePlugin: close album: %s", txn.get_response());
        try
		{
            Publishing.RESTSupport.XmlDocument doc = Publishing.RESTSupport.XmlDocument.parse_string( txn.get_response(), Transaction.validate_xml);
            Xml.Node* response = doc.get_root_node();
            string sessionToken = doc.get_named_child( response, "sessionToken" )->get_content();
			session.set_usertoken( sessionToken );
			session.set_albumtoken( null );
        }
		catch (Spit.Publishing.PublishingError err)
		{
            debug("ERROR: on_close_album_complete");
            do_show_error(err);
            return;
        }
        do_show_success_pane();
    }
    
    /**
     * Event triggered when the close album transaction fails due to a network error.
     */
    private void on_close_album_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_close_album_error");
        bad_txn.completed.disconnect(on_close_album_complete);
        bad_txn.network_error.disconnect(on_close_album_error);
		// ignore this error
//        on_network_error(bad_txn, err);
        do_show_success_pane();
    }

		
    /**
     * Action to display the success pane in the publishing dialog.
     */
    private void do_show_success_pane()
	{
        debug("ACTION: installing success pane");
		if( get_show_album() && session.get_albumticket() != null )
		{
			try
			{
				GLib.Process.spawn_command_line_async( "xdg-open " + session.get_albumticket() );
			}
			catch( GLib.SpawnError e )
			{
			}
		}
        host.set_service_locked(false);
        host.install_success_pane();
    }
    
    /**
     * Helper event to handle network errors.
     */
    private void on_network_error( Publishing.RESTSupport.Transaction bad_txn, Spit.Publishing.PublishingError err )
	{
        debug("EVENT: on_network_error");
        do_show_error(err);
    }
    
    /**
     * Action to display an error to the user.
     */
    private void do_show_error(Spit.Publishing.PublishingError e)
	{
        debug("ACTION: do_show_error");
        string error_type = "UNKNOWN";
        if (e is Spit.Publishing.PublishingError.NO_ANSWER)
		{
            do_show_authentication_pane(AuthenticationPane.Mode.FAILED_RETRY_USER);
            return;
        } else if(e is Spit.Publishing.PublishingError.COMMUNICATION_FAILED) {
            error_type = "COMMUNICATION_FAILED";
        } else if(e is Spit.Publishing.PublishingError.PROTOCOL_ERROR) {
            error_type = "PROTOCOL_ERROR";
        } else if(e is Spit.Publishing.PublishingError.SERVICE_ERROR) {
            error_type = "SERVICE_ERROR";
        } else if(e is Spit.Publishing.PublishingError.MALFORMED_RESPONSE) {
            error_type = "MALFORMED_RESPONSE";
        } else if(e is Spit.Publishing.PublishingError.LOCAL_FILE_ERROR) {
            error_type = "LOCAL_FILE_ERROR";
        } else if(e is Spit.Publishing.PublishingError.EXPIRED_SESSION) {
            error_type = "EXPIRED_SESSION";
        }
        
        debug("Unhandled error: type=%s; message='%s'".printf(error_type, e.message));
        do_show_error_message(_("An error message occurred when publishing to Rajce. Please try again."));
    }
    
    /**
     * Action to display an error message to the user.
     */
    private void do_show_error_message(string message)
	{
        debug("ACTION: do_show_error_message");
        host.install_static_message_pane(message, Spit.Publishing.PluginHost.ButtonMode.CLOSE);
    }
    
}

// Rajce Album
internal class Album
{
    public int id;
    public string albumName;
    public string url;
    public string thumbUrl;
    public string createDate;
    public string updateDate;
    public bool hidden;
    public bool secure;
	public int photoCount;

    public Album( int id, string albumName, string url, string thumbUrl, string createDate, string updateDate, bool hidden, bool secure, int photoCount )
	{
        this.id = id;
        this.albumName = albumName;
        this.url = url;
        this.thumbUrl = thumbUrl;
        this.createDate = createDate;
        this.updateDate = updateDate;
        this.hidden = hidden;
        this.secure = secure;
        this.photoCount = photoCount;
    }
	public static int compare_albums(Album? a, Album? b)
	{
		if( a == null && b == null )
		{
			return 0;
		}
		else if( a == null && b != null )
		{
			return 1;
		}
		else if( a != null && b == null )
		{
			return -1;
		}
		return( b.updateDate.ascii_casecmp( a.updateDate ) );
	}
}

// Uploader
internal class Uploader : Publishing.RESTSupport.BatchUploader
{
    private PublishingParameters parameters;
	private string url;

    public Uploader(Session session, string url, Spit.Publishing.Publishable[] publishables, PublishingParameters parameters)
	{
        base(session, publishables);
        this.parameters = parameters;
		this.url = url;
    }

    protected override Publishing.RESTSupport.Transaction create_transaction( Spit.Publishing.Publishable publishable )
	{
        return new AddPhotoTransaction((Session) get_session(), url, parameters, publishable);
    }
}

// UI elements

/**
 * The authentication pane used when asking service URL, user name and password
 * from the user.
 */
internal class AuthenticationPane : Spit.Publishing.DialogPane, Object
{
    public enum Mode
	{
        INTRO,
        FAILED_RETRY_USER
    }
    private static string INTRO_MESSAGE = _("Enter email and password associated with your Rajce account.");
    private static string FAILED_RETRY_USER_MESSAGE = _("Invalid email and/or password. Please try again");

    private Gtk.Box pane_widget = null;
    private Gtk.Builder builder;
    private Gtk.Entry username_entry;
    private Gtk.Entry password_entry;
    private Gtk.CheckButton remember_checkbutton;
    private Gtk.Button login_button;
	private bool crypt = true;

    public signal void login( string user, string token, bool remember );

    public AuthenticationPane( RajcePublisher publisher, Mode mode = Mode.INTRO )
	{
        this.pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        try
		{
            builder = new Gtk.Builder();
            builder.add_from_resource (Resources.RESOURCE_PATH +
                    "/rajce_authentication_pane.ui");
            builder.connect_signals(null);
            var content = builder.get_object ("content") as Gtk.Box;
            Gtk.Label message_label = builder.get_object("message_label") as Gtk.Label;
            switch (mode)
			{
                case Mode.INTRO:
                    message_label.set_text(INTRO_MESSAGE);
                    break;

                case Mode.FAILED_RETRY_USER:
                    message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                        "Invalid User Email or Password"), FAILED_RETRY_USER_MESSAGE));
                    break;
            }
            username_entry = builder.get_object ("username_entry") as Gtk.Entry;
            string? persistent_username = publisher.get_username();
            if (persistent_username != null)
			{
                username_entry.set_text(persistent_username);
            }
            password_entry = builder.get_object ("password_entry") as Gtk.Entry;
            string? persistent_token = publisher.get_token();
            if (persistent_token != null)
			{
                password_entry.set_text(persistent_token);
				this.crypt = false;
            }
			else
			{
				this.crypt = true;
			}
            remember_checkbutton = builder.get_object ("remember_checkbutton") as Gtk.CheckButton;
            remember_checkbutton.set_active(publisher.get_remember());
            login_button = builder.get_object("login_button") as Gtk.Button;

			Gtk.Label label2 = builder.get_object("label2") as Gtk.Label;
			Gtk.Label label3 = builder.get_object("label3") as Gtk.Label;

			label2.set_label(_("_Email address") );
			label3.set_label(_("_Password") );
			remember_checkbutton.set_label(_("_Remember") );
			login_button.set_label(_("Log in") );
			
            username_entry.changed.connect(on_user_changed);
            password_entry.changed.connect(on_password_changed);
            login_button.clicked.connect(on_login_button_clicked);
            content.parent.remove (content);
            pane_widget.add (content);
            publisher.get_host().set_dialog_default_widget(login_button);
        }
		catch (Error e)
		{
            warning("Could not load UI: %s", e.message);
        }
    }
    
    public Gtk.Widget get_default_widget()
	{
        return login_button;
    }

    private void on_login_button_clicked()
	{
		string token = password_entry.get_text();
		if( this.crypt )
		{
			token = GLib.Checksum.compute_for_string( GLib.ChecksumType.MD5, token );
		}
        login(username_entry.get_text(), token, remember_checkbutton.get_active());
    }

    private void on_user_changed()
	{
        update_login_button_sensitivity();
    }

    private void on_password_changed()
	{
		this.crypt = true;
        update_login_button_sensitivity();
    }
    
    private void update_login_button_sensitivity()
	{
        login_button.set_sensitive(username_entry.text_length > 0 &&
                                   password_entry.text_length > 0);
    }
    
    public Gtk.Widget get_widget()
	{
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry()
	{
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed()
	{
        username_entry.grab_focus();
        password_entry.set_activates_default(true);
        login_button.can_default = true;
        update_login_button_sensitivity();
    }
    public void on_pane_uninstalled() {}
  
}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object
{
	RajcePublisher publisher;
    private Album[] albums;
    private string username;
	
	private Gtk.Builder builder = null;
    private Gtk.Box pane_widget = null;
    private Gtk.Label login_identity_label = null;
    private Gtk.Label publish_to_label = null;
    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.ComboBoxText existing_albums_combo = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.CheckButton hide_check = null;
    private Gtk.CheckButton show_check = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;

    public signal void publish( PublishingParameters parameters );
    public signal void logout();

    public PublishingOptionsPane( RajcePublisher publisher, string username, Album[] albums )
	{
        this.username = username;
        this.albums = albums;
        this.publisher = publisher;
        this.pane_widget = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		
        try
		{
		    this.builder = new Gtk.Builder();
			builder.add_from_resource (Resources.RESOURCE_PATH + "/rajce_publishing_options_pane.ui");
            builder.connect_signals(null);
			
		    pane_widget = (Gtk.Box) builder.get_object("rajce_pane_widget");
		    login_identity_label = (Gtk.Label) builder.get_object("login_identity_label");
		    publish_to_label = (Gtk.Label) builder.get_object("publish_to_label");
		    use_existing_radio = (Gtk.RadioButton) builder.get_object("use_existing_radio");
		    existing_albums_combo = (Gtk.ComboBoxText) builder.get_object("existing_albums_combo");
		    create_new_radio = (Gtk.RadioButton) builder.get_object("create_new_radio");
		    new_album_entry = (Gtk.Entry) builder.get_object("new_album_entry");
		    hide_check = (Gtk.CheckButton) builder.get_object("hide_check");
			hide_check.set_label(_("_Hide album") );
		    show_check = (Gtk.CheckButton) builder.get_object("show_check");
		    publish_button = (Gtk.Button) builder.get_object("publish_button");
		    logout_button = (Gtk.Button) builder.get_object("logout_button");

		    hide_check.set_active( publisher.get_hide_album() );
		    show_check.set_active( publisher.get_show_album() );
		    login_identity_label.set_label(_("You are logged into Rajce as %s.").printf(username));
		    publish_to_label.set_label(_("Photos will appear in:"));
			use_existing_radio.set_label(_("An _existing album:") );
			create_new_radio.set_label(_("A _new album named:") );
			show_check.set_label(_("Open target _album in browser") );
			publish_button.set_label(_("_Publish") );
			logout_button.set_label(_("_Logout") );
			
		    use_existing_radio.clicked.connect(on_use_existing_radio_clicked);
		    create_new_radio.clicked.connect(on_create_new_radio_clicked);
		    new_album_entry.changed.connect(on_new_album_entry_changed);
		    logout_button.clicked.connect(on_logout_clicked);
		    publish_button.clicked.connect(on_publish_clicked);
        }
		catch (Error e)
		{
            warning("Could not load UI: %s", e.message);
        }
		
    }

    private void on_publish_clicked()
	{
        bool show_album = show_check.get_active();
		publisher.set_show_album( show_album );
        if (create_new_radio.get_active())
		{
            string album_name = new_album_entry.get_text();
            bool hide_album = hide_check.get_active();
			publisher.set_hide_album( hide_album );
            publish( new PublishingParameters.to_new_album( album_name, hide_album ) );
        }
		else
		{
            int id = albums[existing_albums_combo.get_active()].id;
			string album_name = albums[existing_albums_combo.get_active()].albumName;
            publish( new PublishingParameters.to_existing_album( album_name, id ) );
        }
    }

    private void on_use_existing_radio_clicked()
	{
        existing_albums_combo.set_sensitive(true);
        new_album_entry.set_sensitive(false);
        existing_albums_combo.grab_focus();
        update_publish_button_sensitivity();
        hide_check.set_sensitive(false);
    }

    private void on_create_new_radio_clicked()
	{
        new_album_entry.set_sensitive(true);
        existing_albums_combo.set_sensitive(false);
        new_album_entry.grab_focus();
        update_publish_button_sensitivity();
        hide_check.set_sensitive(true);
    }

    private void on_logout_clicked()
	{
        logout();
    }
    private void update_publish_button_sensitivity()
	{
        string album_name = new_album_entry.get_text();
        publish_button.set_sensitive( album_name.strip() != "" || !create_new_radio.get_active());
    }
    private void on_new_album_entry_changed()
	{
        update_publish_button_sensitivity();
    }
    public void installed()
	{
        for (int i = 0; i < albums.length; i++)
		{
			// TODO: sort albums according to their updateDate property
            existing_albums_combo.append_text( albums[i].albumName );
        }
        if (albums.length == 0)
		{
            existing_albums_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
        }
		else
		{
            existing_albums_combo.set_active(0);
            existing_albums_combo.set_sensitive(true);
            use_existing_radio.set_sensitive(true);
        }
        create_new_radio.set_active(true);
		on_create_new_radio_clicked();
    }
    
    protected void notify_publish(PublishingParameters parameters)
	{
        publish( parameters );
    }
    
    protected void notify_logout()
	{
        logout();
    }

    public Gtk.Widget get_default_widget()
	{
        return logout_button;
    }
	public Gtk.Widget get_widget()
	{
        return pane_widget;
    }
    
    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry()
	{
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }
    
    public void on_pane_installed()
	{
        installed();
        publish.connect(notify_publish);
        logout.connect(notify_logout);
    }
    
    public void on_pane_uninstalled()
	{
        publish.disconnect(notify_publish);
        logout.disconnect(notify_logout);
    }
}

internal class PublishingParameters
{
    public string? album_name;
    public bool? album_hidden;
    public int? album_id;
    
    private PublishingParameters()
	{
    }
    public PublishingParameters.to_new_album( string album_name, bool album_hidden )
	{
        this.album_name = album_name;
        this.album_hidden = album_hidden;
		this.album_id = 0;
    }
    public PublishingParameters.to_existing_album( string album_name, int album_id )
	{
        this.album_name = album_name;
        this.album_hidden = null;
		this.album_id = album_id;
    }
}

// REST support classes
/**
 * Session class that keeps track of the credentials
 */
internal class Session : Publishing.RESTSupport.Session {
    private string? usertoken = null;
    private string? albumtoken = null;
    private string? albumticket = null;
    private string? username = null;
    private int? userid = null;
    private int? maxsize = null;
    private int? quality = null;

    public Session()
	{
        base("");
    }

    public override bool is_authenticated()
	{
        return (userid != null && usertoken != null && username != null);
    }

    public void authenticate(string token, string name, int id, int maxsize, int quality )
	{
        this.usertoken = token;
        this.username = name;
        this.userid = id;
        this.maxsize = maxsize;
        this.quality = quality;
    }

    public void deauthenticate()
	{
        usertoken = null;
    	albumtoken = null;
    	albumticket = null;
        username = null;
        userid = null;
	    maxsize = null;
	    quality = null;
    }
	
    public void set_usertoken( string? usertoken ){ this.usertoken = usertoken; }
    public void set_albumtoken( string? albumtoken ){ this.albumtoken = albumtoken; }
    public void set_albumticket( string? albumticket ){ this.albumticket = albumticket; }
	
    public string get_usertoken() { return usertoken; }
    public string get_albumtoken() { return albumtoken; }
    public string get_albumticket() { return albumticket; }
    public string get_username() { return username; }
//    public int get_userid() { return userid; }
    public int get_maxsize() { return maxsize; }
//    public int get_quality() { return quality; }
}

internal class ArgItem
{
    public string? key;
    public string? val;
    public ArgItem[] children;
	
    public ArgItem( string? k, string? v )
	{
		key = k;
		val = v;
		children = new ArgItem[0];
	}
    public void AddChild( ArgItem child )
	{
		children += child;
	}
    public void AddChildren( ArgItem[] newchildren )
	{
		foreach( ArgItem child in newchildren )
		{
			AddChild( child );
		}
	}
    ~ArgItem()
	{
		foreach( ArgItem child in children )
		{
			child = null;			
		}
	}
}

/// <summary>
/// implementation of Rajce Live API
/// </summary>
internal class LiveApiRequest
{
    private ArgItem[] _params;
    private string _cmd;
    public LiveApiRequest( string cmd )
    {
        _params = new ArgItem[0];
        _cmd = cmd;
    }
    /// <summary>
    /// add string parameter
    /// </summary>
    public void AddParam( string name, string val )
    {
        _params += new ArgItem( name, val );
    }
    /// <summary>
    /// add boolean parameter
    /// </summary>
    public void AddParamBool( string name, bool val )
    {
        AddParam( name, val ? "1" : "0" );
    }
    /// <summary>
    /// add integer parameter
    /// </summary>
    public void AddParamInt( string name, int val )
    {
        AddParam( name, val.to_string() );
    }
/*    /// <summary>
    /// add double parameter
    /// </summary>
    public void AddParamDouble( string name, double val )
    {
        AddParam( name, val.to_string() );
    }
*/    /// <summary>
    /// add compound parameter
    /// </summary>
    public void AddParamNode( string name, ArgItem[] val )
    {
		ArgItem newItem = new ArgItem( name, null );
		newItem.AddChildren( val );
        _params += newItem; 
    }
    /// <summary>
    /// create XML fragment containing all parameters
    /// </summary>
    public string Params2XmlString( bool urlencode = true )
    {
        Xml.Doc* doc = new Xml.Doc( "1.0" );
        Xml.Node* root = new Xml.Node( null, "request" );
        doc->set_root_element( root );
        root->new_text_child( null, "command", _cmd );
        Xml.Node* par = root->new_text_child( null, "parameters", "" );
		foreach( ArgItem arg in _params )
		{
        	WriteParam( par, arg );
		}
        string xmlstr;
        doc->dump_memory_enc( out xmlstr );
        delete doc;
		if( urlencode )
		{
        	return Soup.URI.encode( xmlstr, "&;" );
		}
		return xmlstr;
    }
    /// <summary>
    /// write single or compound (recursively) parameter into XML
    /// </summary>
    private static void WriteParam( Xml.Node* node, ArgItem arg )
    {
		if( arg.children.length == 0 )
		{
	        node->new_text_child( null, arg.key, arg.val );
		}
		else
		{
	        Xml.Node* subnode = node->new_text_child( null, arg.key, "" );
			foreach( ArgItem child in arg.children )
			{
		    	WriteParam( subnode, child );
			}
		}
    }
}


/**
 * Generic REST transaction class.
 *
 * This class implements the generic logic for all REST transactions used
 * by the Rajce publishing plugin.
 */
internal class Transaction : Publishing.RESTSupport.Transaction
{
    public Transaction(Session session)
	{
        base(session);
    }

    public static string? validate_xml(Publishing.RESTSupport.XmlDocument doc)
	{
        Xml.Node* root = doc.get_root_node();
		if( root == null )
		{
            return "No XML returned from server";
		}
        string name = root->name;
        
        // treat malformed root as an error condition
        if( name == null || name != "response" )
		{
            return "No response from Rajce in XML";
		}
        Xml.Node* errcode;
        Xml.Node* result;
        try
		{
            errcode = doc.get_named_child(root, "errorCode");
            result = doc.get_named_child(root, "result");
        }
		catch (Spit.Publishing.PublishingError err)
		{
            return null;
        }
        return "999 Rajce Error [%d]: %s".printf( int.parse( errcode->get_content() ), result->get_content() );
    }
}

/**
 * Transaction used to implement the network login interaction.
 */
internal class SessionLoginTransaction : Transaction
{
    public SessionLoginTransaction(Session session, string url, string username, string token)
	{
		debug("SessionLoginTransaction: URL: %s", url);
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "login" );
		req.AddParam( "clientID", "RajceShotwellPlugin" ); 
		req.AddParam( "currentVersion", "1.1.1.1" ); 
		req.AddParam( "login", username ); 
		req.AddParam( "password", token ); 
		string xml = req.Params2XmlString();
        add_argument("data", xml);
    }
}

/**
 * Transaction used to implement the get albums interaction.
 */
internal class GetAlbumsTransaction : Transaction
{
    public GetAlbumsTransaction(Session session, string url)
	{
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "getAlbumList" );
		req.AddParam( "token", session.get_usertoken() );
		ArgItem[] columns = new ArgItem[0];
		columns += new ArgItem( "column", "viewCount" );
		columns += new ArgItem( "column", "isFavourite" );
		columns += new ArgItem( "column", "descriptionHtml" );
		columns += new ArgItem( "column", "coverPhotoID" );
		columns += new ArgItem( "column", "localPath" );
		req.AddParamNode( "columns", columns );
		string xml = req.Params2XmlString();
        add_argument("data", xml );
    }
}

/**
 * Transaction used to implement the create album interaction.
 */
internal class CreateAlbumTransaction : Transaction
{
    public CreateAlbumTransaction( Session session, string url, string albumName, bool hidden )
	{
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "createAlbum" );
		req.AddParam( "token", session.get_usertoken() ); 
		req.AddParam( "albumName", albumName ); 
		req.AddParam( "albumDescription", "" ); 
		req.AddParamBool( "albumVisible", !hidden ); 
		string xml = req.Params2XmlString();
        add_argument("data", xml);
    }
}

/**
 * Transaction used to implement the open album interaction.
 */
internal class OpenAlbumTransaction : Transaction
{
    public OpenAlbumTransaction( Session session, string url, int albumID )
	{
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "openAlbum" );
		req.AddParam( "token", session.get_usertoken() ); 
		req.AddParamInt( "albumID", albumID ); 
		string xml = req.Params2XmlString();
        add_argument("data", xml);
    }
}

/**
 * Transaction used to implement the close album interaction.
 */
internal class GetAlbumUrlTransaction : Transaction
{
    public GetAlbumUrlTransaction( Session session, string url )
	{
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "getAlbumUrl" );
		req.AddParam( "token", session.get_usertoken() ); 
		req.AddParam( "albumToken", session.get_albumtoken() ); 
		string xml = req.Params2XmlString();
        add_argument("data", xml);
    }
}

/**
 * Transaction used to implement the close album interaction.
 */
internal class CloseAlbumTransaction : Transaction
{
    public CloseAlbumTransaction( Session session, string url )
	{
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "closeAlbum" );
		req.AddParam( "token", session.get_usertoken() ); 
		req.AddParam( "albumToken", session.get_albumtoken() ); 
		string xml = req.Params2XmlString();
        add_argument("data", xml);
    }
}

/**
 * Transaction used to implement the get categories interaction.
 */
internal class GetCategoriesTransaction : Transaction
{
    public GetCategoriesTransaction( Session session, string url )
	{
        base.with_endpoint_url(session, url);
		LiveApiRequest req = new LiveApiRequest( "getCategories" );
		req.AddParam( "token", session.get_usertoken() ); 
		string xml = req.Params2XmlString();
        add_argument("data", xml);
    }
}

/**
 * Transaction used to implement the upload photo.
 */
private class AddPhotoTransaction : Publishing.RESTSupport.UploadTransaction
{
    private PublishingParameters parameters = null;

    public AddPhotoTransaction(Session session, string url, PublishingParameters parameters, Spit.Publishing.Publishable publishable)
	{
        base.with_endpoint_url( session, publishable, url );
        this.parameters = parameters;
        
        debug("RajcePlugin: Uploading photo %s to%s album %s", publishable.get_serialized_file().get_basename(), ( parameters.album_id > 0 ? "" : " new" ), parameters.album_name );

		string basename = publishable.get_param_string( Spit.Publishing.Publishable.PARAM_STRING_BASENAME );
		string comment = publishable.get_param_string( Spit.Publishing.Publishable.PARAM_STRING_COMMENT );
		string pubname = publishable.get_publishing_name();
		
		int width = session.get_maxsize();
		int height = session.get_maxsize();
		
		LiveApiRequest req = new LiveApiRequest( "addPhoto" );
		req.AddParam( "token", session.get_usertoken() ); 
		req.AddParamInt( "width", width ); 
		req.AddParamInt( "height", height ); 
		req.AddParam( "albumToken", session.get_albumtoken() ); 
		req.AddParam( "photoName", pubname ); 
		req.AddParam( "fullFileName", basename ); 
		req.AddParam( "description", ( comment != null ? comment : "" ) ); 
		string xml = req.Params2XmlString( false );
        add_argument( "data", xml );
		
        GLib.HashTable<string, string> disposition_table = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
        disposition_table.insert("name", "photo");
        disposition_table.insert("filename", Soup.URI.encode( basename, null ) );
        set_binary_disposition_table( disposition_table );
    }

}


}

