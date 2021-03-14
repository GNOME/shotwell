/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

[CCode (
    cprefix="GP",
    lower_case_cprefix="gp_"
)]
namespace GPhoto {
    [SimpleType]
    [CCode (
        cname="CameraAbilities",
        destroy_function="",
        cheader_filename="gphoto2/gphoto2-abilities-list.h"
    )]
    public struct CameraAbilities {
        public string model;
        public int status;
        public PortType port;
        public string speed;
        public CameraOperation operations;
        public CameraFileOperation file_operations;
        public CameraFolderOperation folder_operations;
        public int usb_vendor;
        public int usb_product;
        public int usb_class;
        public int usb_protocol;
    }
    
    [Compact]
    [CCode (
        cname="CameraAbilitiesList",
        cprefix="gp_abilities_list_",
        free_function="gp_abilities_list_free",
        cheader_filename="gphoto2/gphoto2-abilities-list.h"
    )]
    public class CameraAbilitiesList {
        [CCode (cname="gp_abilities_list_new")]
        public static Result create(out CameraAbilitiesList abilitiesList);
        public Result load(Context context);
        public Result reset();
        public Result detect(PortInfoList portList, CameraList cameraList, Context context);
        public int count();
        public int lookup_model(string model);
        public Result get_abilities(int index, out CameraAbilities abilities);
    }
    
    [Compact]
    [CCode (
        cname="Camera",
        ref_function="GPHOTO_REF_CAMERA",
        unref_function="gp_camera_unref",
        free_function="gp_camera_free",
        cheader_filename="gphoto2/gphoto2-camera.h,gphoto.h"
    )]
    public class Camera {
        [CCode (cname="gp_camera_new")]
        public static Result create(out Camera camera);
        public Result init(Context context);
        public Result exit(Context context);
        public Result get_port_info(out PortInfo info);
        public Result set_port_info(PortInfo info);
        public Result get_abilities(out CameraAbilities abilities);
        public Result set_abilities(CameraAbilities abilities);
        public Result get_storageinfo([CCode (array_length_pos=1.1)]out CameraStorageInformation[] sifs, Context context);
        
        // Folders
        [CCode (cname="gp_camera_folder_list_folders")]
        public Result list_folders(string folder, CameraList list, Context context);
        [CCode (cname="gp_camera_folder_list_files")]
        public Result list_files(string folder, CameraList list, Context context);
        [CCode (cname="gp_camera_folder_delete_all")]
        public Result delete_all_files(string folder, Context context);
        [CCode (cname="gp_camera_folder_put_file")]
        public Result put_file(string folder, string filename, CameraFileType type, CameraFile file, Context context);
        [CCode (cname="gp_camera_folder_make_dir")]
        public Result make_dir(string folder, string name, Context context);
        [CCode (cname="gp_camera_folder_remove_dir")]
        public Result remove_dir(string folder, string name, Context context);
        
        // Files
        [CCode (cname="gp_camera_file_get_info")]
        public Result get_file_info(string folder, string file, out CameraFileInfo info, Context context);
        [CCode (cname="gp_camera_file_set_info")]
        public Result set_file_info(string folder, string file, CameraFileInfo info, Context context);
        [CCode (cname="gp_camera_file_get")]
        public Result get_file(string folder, string filename, CameraFileType type, CameraFile file,
            Context context);
        [CCode (cname="gp_camera_file_delete")]
        public Result delete_file(string folder, string filename, Context context);
    }
    
    [Compact]
    [CCode (
        cname="CameraFile",
        cprefix="gp_file_",
        ref_function="GPHOTO_REF_FILE",
        unref_function="gp_file_unref",
        free_function="gp_file_free",
        cheader_filename="gphoto2/gphoto2-file.h,gphoto.h"
    )]
    public class CameraFile {
        [CCode (cname="gp_file_new")]
        public static Result create(out CameraFile file);
        [CCode (cname="gp_file_new_from_fd")]
        public static Result create_from_fd(out CameraFile file, int fd);
        [CCode (cname="gp_file_get_data_and_size")]
        public Result get_data([CCode (array_length_pos=1.1, array_length_type="gulong")]out unowned uint8[] data);
        public Result save(string filename);
        public Result slurp(uint8[] data, out size_t readlen);
    }
    
    [SimpleType]
    [CCode (
        cname="CameraFileInfo",
        destroy_function="",
        cheader_filename="gphoto2/gphoto2-filesys.h"
    )]
    public struct CameraFileInfo {
        public CameraFileInfoPreview preview;
        public CameraFileInfoFile file;
        public CameraFileInfoAudio audio;
    }
    
    [SimpleType]
    [CCode (
        cname="CameraFileInfoAudio",
        cheader_filename="gphoto2/gphoto2-filesys.h"
    )]
    public struct CameraFileInfoAudio {
    }
    
    [CCode (
        cname="CameraFileInfoFields",
        cheader_filename="gphoto2/gphoto2-filesys.h",
        cprefix="GP_FILE_INFO_"
    )]
    [Flags]
    public enum CameraFileInfoFields {
        NONE,
        TYPE,
        SIZE,
        WIDTH,
        HEIGHT,
        PERMISSIONS,
        STATUS,
        MTIME,
        ALL
    }
    
    [SimpleType]
    [CCode (
        cname="CameraFileInfoFile",
        cheader_filename="gphoto2/gphoto2-filesys.h"
    )]
    public struct CameraFileInfoFile {
        public CameraFileInfoFields fields;
        public CameraFileStatus status;
        public ulong size;
        public char type[64];
        public uint width;
        public uint height;
        public CameraFilePermissions permissions;
        public time_t mtime;
    }
    
    [SimpleType]
    [CCode (
        cname="CameraFileInfoPreview",
        cheader_filename="gphoto2/gphoto2-filesys.h"
    )]
    public struct CameraFileInfoPreview {
        public CameraFileInfoFields fields;
        public CameraFileStatus status;
        public ulong size;
        public char type[64];
        public uint width;
        public uint height;
    }
    
    [CCode (
        cname="CameraFileOperation",
        cheader_filename="gphoto2/gphoto2-abilities-list.h",
        cprefix="GP_FILE_OPERATION_"
    )]
    [Flags]
    public enum CameraFileOperation {
        NONE,
        DELETE,
        PREVIEW,
        RAW,
        AUDIO,
        EXIF
    }
    
    [CCode (
        cname="CameraFilePermissions",
        cheader_filename="gphoto2/gphoto2-filesys.h",
        cprefix="GP_FILE_PERM_"
    )]
    [Flags]
    public enum CameraFilePermissions {
        NONE,
        READ,
        DELETE,
        ALL
    }
    
    [CCode (
        cname="CameraFileStatus",
        cheader_filename="gphoto2/gphoto2-filesys.h",
        cprefix="GP_FILE_STATUS_"
    )]
    public enum CameraFileStatus {
        NOT_DOWNLOADED,
        DOWNLOADED
    }
    
    [CCode (
        cname="CameraFileType",
        cheader_filename="gphoto2/gphoto2-file.h",
        cprefix="GP_FILE_TYPE_"
    )]
    public enum CameraFileType {
        PREVIEW,
        NORMAL,
        RAW,
        AUDIO,
        EXIF,
        METADATA
    }
    
    [CCode (
        cname="CameraFolderOperation",
        cheader_filename="gphoto2/gphoto2-abilities-list.h",
        cprefix="GP_FOLDER_OPERATION_"
    )]
    [Flags]
    public enum CameraFolderOperation {
        NONE,
        DELETE_ALL,
        PUT_FILE,
        MAKE_DIR,
        REMOVE_DIR
    }
    
    [Compact]
    [CCode (
        cname="CameraList",
        cprefix="gp_list_",
        ref_function="GPHOTO_REF_LIST",
        unref_function="gp_list_unref",
        free_function="gp_list_free",
        cheader_filename="gphoto2/gphoto2-list.h,gphoto.h"
    )]
    public class CameraList {
        [CCode (cname="gp_list_new")]
        public static Result create(out CameraList list);
        public int count();
        public Result append(string name, string value);
        public Result reset();
        public Result sort();
        public Result find_by_name(out int index, string name);
        public Result get_name(int index, out unowned string name);
        public Result get_value(int index, out unowned string value);
        public Result set_name(int index, string name);
        public Result set_value(int index, string value);
        public Result populate(string format, int count);
    }
    
    [CCode (
        cname="CameraOperation",
        cheader_filename="gphoto2/gphoto2-abilities-list.h",
        cprefix="GP_OPERATION_"
    )]
    [Flags]
    public enum CameraOperation {
        NONE,
        CAPTURE_IMAGE,
        CAPTURE_VIDEO,
        CAPTURE_AUDIO,
        CAPTURE_PREVIEW,
        CONFIG
    }
    
    [CCode (
        cname="CameraStorageInfoFields",
        cheader_filename="gphoto2/gphoto2-filesys.h",
        cprefix="GP_STORAGEINFO_"
    )]
    [Flags]
    public enum CameraStorageInfoFields {
        BASE,
        LABEL,
        DESCRIPTION,
        ACCESS,
        STORAGETYPE,
        FILESYSTEMTYPE,
        MAXCAPACITY,
        FREESPACEKBYTES,
        FREESPACEIMAGES
    }
    
    [SimpleType]
    [CCode (
        cname="CameraStorageInformation",
        cheader_filename="gphoto2/gphoto2-filesys.h"
    )]
    public struct CameraStorageInformation {
        public CameraStorageInfoFields fields;
        public char basedir[256];
        public char label[256];
        public char description[256];
        public int type;
        public int fstype;
        public int access;
        public ulong capacitykbytes;
        public ulong freekbytes;
        public ulong freeimages;
    }
    
    [Compact]
    [CCode (
        ref_function="GPHOTO_REF_CONTEXT",
        unref_function="gp_context_unref",
        cheader_filename="gphoto2/gphoto2-context.h,gphoto.h"
    )]
    public class Context {
        [CCode (cname="gp_context_new")]
        public Context();
        public void set_idle_func(ContextIdleFunc func);
        public void set_progress_funcs(
            [CCode (delegate_target_pos=3.1)] ContextProgressStartFunc startFunc, 
            [CCode (delegate_target_pos=3.1)] ContextProgressUpdateFunc updateFunc, 
            [CCode (delegate_target_pos=3.1)] ContextProgressStopFunc stopFunc);
        public void set_error_func([CCode (delegate_target_pos=3.1)] ContextErrorFunc errorFunc);
        public void set_status_func([CCode (delegate_target_pos=3.1)] ContextStatusFunc statusFunc);
        public void set_message_func([CCode (delegate_target_pos=3.1)] ContextMessageFunc messageFunc);
    }
    
    public delegate void ContextIdleFunc(Context context);
    
    public delegate void ContextErrorFunc(Context context, string text);
    
    public delegate void ContextStatusFunc(Context context, string text);
    
    public delegate void ContextMessageFunc(Context context, string text);
    
    // TODO: Support for va_args in Vala, esp. for delegates?
    public delegate uint ContextProgressStartFunc(Context context, float target, string text);
    
    public delegate void ContextProgressUpdateFunc(Context context, uint id, float current);
    
    public delegate void ContextProgressStopFunc(Context context, uint id);
    
    [CCode (
        cheader_filename="gphoto2/gphoto2-file.h",
        cprefix="GP_MIME_"
    )]
    namespace MIME {
        public const string WAV;
        public const string RAW;
        public const string PNG;
        public const string PGM;
        public const string PPM;
        public const string PNM;
        public const string JPEG;
        public const string TIFF;
        public const string BMP;
        public const string QUICKTIME;
        public const string AVI;
        public const string CRW;
        public const string UNKNOWN;
        public const string EXIF;
        public const string MP3;
        public const string OGG;
        public const string WMA;
        public const string ASF;
        public const string MPEG;
    }
    
    [SimpleType]
    [CCode (
        destroy_function="",
        cheader_filename="gphoto2/gphoto2-port-info-list.h"
    )]
    public struct PortInfo {
        [CCode (cname="gp_port_info_get_path")]
        public int get_path(out unowned string path);
        [CCode (cname="gp_port_info_set_path")]
        public int set_path(string path);
        [CCode (cname="gp_port_info_get_name")]
        public int get_name(out unowned string name);
        [CCode (cname="gp_port_info_set_name")]
        public int set_name(string path);
        [CCode (cname="gp_port_info_get_library_filename")]
        public int get_library_filename(out unowned string lib);
        [CCode (cname="gp_port_info_set_library_filename")]
        public int set_library_filename(string lib);
    }
    
    [Compact]
    [CCode (
        free_function="gp_port_info_list_free",
        cheader_filename="gphoto2/gphoto2-port-info-list.h"
    )]
    public class PortInfoList {
        [CCode (cname="gp_port_info_list_new")]
        public static Result create(out PortInfoList list);
        public Result load();
        public int count();
        public int lookup_name(string name);
        public int lookup_path(string name);
        public Result get_info(int index, out PortInfo info);
    }
    
    [CCode (
        cheader_filename="gphoto2/gphoto2-port-info-list.h",
        cprefix="GP_PORT_"
    )]
    [Flags]
    public enum PortType {
        NONE,
        SERIAL,
        USB,
        DISK,
        PTPIP
    }
    
    [CCode (
        cname="int",
        cheader_filename="gphoto2/gphoto2-result.h,gphoto2/gphoto2-port-result.h",
        cprefix="GP_ERROR_"
    )]
    public enum Result {
        [CCode (cname="GP_OK")]
        OK,
        [CCode (cname="GP_ERROR")]
        ERROR,
        BAD_PARAMETERS,
        NO_MEMORY,
        LIBRARY,
        UNKNOWN_PORT,
        NOT_SUPPORTED,
        IO,
        FIXED_LIMIT_EXCEEDED,
        TIMEOUT,
        IO_SUPPORTED_SERIAL,
        IO_SUPPORTED_USB,
        IO_INIT,
        IO_READ,
        IO_WRITE,
        IO_UPDATE,
        IO_SERIAL_SPEED,
        IO_USB_CLEAR_HALT,
        IO_USB_FIND,
        IO_USB_CLAIM,
        IO_LOCK,
        HAL,
        CORRUPTED_DATA,
        FILE_EXISTS,
        MODEL_NOT_FOUND,
        DIRECTORY_NOT_FOUND,
        FILE_NOT_FOUND,
        DIRECTORY_EXISTS,
        CAMERA_BUSY,
        PATH_NOT_ABSOLUTE,
        CANCEL,
        CAMERA_ERROR,
        OS_FAILURE;
        
        [CCode (cname="gp_port_result_as_string")]
        public unowned string as_string();
        
        public string to_full_string() {
            return "%s (%d)".printf(as_string(), this);
        }
    }
    
    [CCode (
        cheader_filename="gphoto2/gphoto2-version.h",
        cprefix="GP_VERSION_"
    )]
    public enum VersionVerbosity {
        SHORT,
        VERBOSE
    }
    
    public unowned string library_version(VersionVerbosity verbosity);
}

