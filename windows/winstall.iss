[Setup]
AppName=Shotwell
AppPublisher=Yorba Foundation
AppPublisherURL=http://yorba.org
AppVerName=Shotwell 0.7.1+trunk
DefaultDirName={pf}\Shotwell
DefaultGroupName=Shotwell
LicenseFile=COPYING
OutputDir=.
SourceDir=..
Uninstallable=yes

[Icons]
Name: "{commonprograms}\{groupname}\Shotwell"; Filename: "{app}\bin\shotwell.exe"

[Files]
Source: "c:\MinGW\bin\freetype6.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\gdk-pixbuf-query-loaders.exe"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\intl.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libiconv-2.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libatk-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libcairo-2.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libcroco-0.6-3.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libexif-12.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libexiv2-6.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libexpat-1.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libfontconfig-1.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgdk_pixbuf-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgdk-win32-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgio-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libglib-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgmodule-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgobject-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgsf-1-114.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgthread-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgtk-win32-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libjpeg-7.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libjpeg-8.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpango-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpangocairo-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpangoft2-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpangowin32-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpng12-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpng14-14.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\librsvg-2-2.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libxml2-2.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\sqlite3.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\zlib1.dll"; DestDir: "{app}\bin"

Source: "c:\MinGW\lib\gtk-2.0\2.10.0\loaders\libpixbufloader-jpeg.dll"; DestDir: "{app}\lib\gtk-2.0\2.10.0\loaders"
Source: "c:\MinGW\lib\gtk-2.0\2.10.0\loaders\libpixbufloader-png.dll"; DestDir: "{app}\lib\gtk-2.0\2.10.0\loaders"
Source: "c:\MinGW\lib\gtk-2.0\2.10.0\loaders\svg_loader.dll"; DestDir: "{app}\lib\gtk-2.0\2.10.0\loaders"

Source: "icons\*"; DestDir: "{app}\share\shotwell\icons"
Source: "ui\*"; DestDir: "{app}\share\shotwell\ui"
Source: "shotwell.exe"; DestDir: "{app}\bin\"

[Run]
Filename: "cmd"; Parameters: "/c mkdir etc\gtk-2.0 & bin\gdk-pixbuf-query-loaders.exe > etc\gtk-2.0\gdk-pixbuf.loaders"; WorkingDir: "{app}"; Flags: runhidden

[UninstallDelete]
Type: files; Name: "{app}\etc\gtk-2.0\gdk-pixbuf.loaders"
Type: dirifempty; Name: "{app}\etc\gtk-2.0"
Type: dirifempty; Name: "{app}\etc"






