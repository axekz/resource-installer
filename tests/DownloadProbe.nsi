; Test-only executable; never included in the distributed portable tool.
Unicode true
SilentInstall silent
RequestExecutionLevel user
OutFile "..\.cache\DownloadProbe.exe"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!addplugindir /x86-unicode "..\.cache\inetc\Plugins\x86-unicode"
Section
  ${GetParameters} $0
  ${GetOptions} $0 "/URL=" $1
  ${GetOptions} $0 "/OUTPUT=" $2
  ${If} $1 == ""
  ${OrIf} $2 == ""
    SetErrorLevel 2
    Quit
  ${EndIf}
  inetc::get /SILENT /CONNECTTIMEOUT 2 /RECEIVETIMEOUT 2 /NOCOOKIES "$1" "$2" /END
  Pop $3
  WriteINIStr "$2.ini" "Download" "Result" "$3"
  ${If} $3 != "OK"
    Delete "$2"
    SetErrorLevel 1
  ${EndIf}
SectionEnd
