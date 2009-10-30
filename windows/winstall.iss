[Setup]
AppName=Shotwell
AppPublisher=Yorba Foundation
AppPublisherURL=http://yorba.org
AppVerName=Shotwell 0.3.1
DefaultDirName={pf}\Shotwell
DefaultGroupName=Shotwell
LicenseFile=COPYING
OutputDir=.
SourceDir=..
Uninstallable=yes

[Icons]
Name: "{commonprograms}\{groupname}\Shotwell"; Filename: "{app}\bin\shotwell.exe"

[Files]
Source: "c:\MinGW\bin\gspawn-win32-helper.exe"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\gspawn-win32-helper-console.exe"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\intl.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\jpeg62.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libatk-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libcairo-2.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libexif-12.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgconf-2-4.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgdk_pixbuf-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgdk-win32-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgio-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libglib-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgmodule-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgobject-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgthread-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libgtk-win32-2.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libORBit-2-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpango-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpangocairo-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpangowin32-1.0-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\libpng12-0.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\sqlite3.dll"; DestDir: "{app}\bin"
Source: "c:\MinGW\bin\zlib1.dll"; DestDir: "{app}\bin"

Source: "c:\MinGW\etc\gconf\2\*"; DestDir: "{app}\etc\gconf\2"; Flags: recursesubdirs
Source: "c:\MinGW\etc\gtk-2.0\gdk-pixbuf.loaders"; DestDir: "{app}\etc\gtk-2.0"

Source: "c:\MinGW\lib\GConf\2\libgconfbackend-xml.dll"; DestDir: "{app}\lib\GConf\2"
Source: "c:\MinGW\lib\gtk-2.0\2.10.0\engines\libwimp.dll"; DestDir: "{app}\lib\gtk-2.0\2.10.0\engines"
Source: "c:\MinGW\lib\gtk-2.0\2.10.0\loaders\libpixbufloader-jpeg.dll"; DestDir: "{app}\lib\gtk-2.0\2.10.0\loaders"
Source: "c:\MinGW\lib\gtk-2.0\2.10.0\loaders\libpixbufloader-png.dll"; DestDir: "{app}\lib\gtk-2.0\2.10.0\loaders"

Source: "c:\MinGW\libexec\gconfd-2.exe"; DestDir: "{app}\libexec"

Source: "icons\*"; DestDir: "{app}\share\shotwell\icons"
Source: "ui\*"; DestDir: "{app}\share\shotwell\ui"
Source: "shotwell.exe"; DestDir: "{app}\bin\"

