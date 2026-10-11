# -*- coding: utf-8 -*-
Unicode true
ManifestDPIAware true
Name "AXE GOKZ Resource Installer"
Caption "AXE GOKZ Resource Installer"
OutFile "..\dist\AXE-Resource-Installer.exe"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
BrandingText " "
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "AXE GOKZ Resource Installer"
VIAddVersionKey "FileDescription" "Resources for standalone CS:GO Legacy (4465480)"
VIAddVersionKey "FileVersion" "1.0.0"
VIAddVersionKey "LegalCopyright" "AXE GOKZ contributors"

!include "MUI2.nsh"
!define MUI_ICON "..\assets\axe-gokz.ico"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "FileFunc.nsh"
!addplugindir /x86-unicode "..\.cache\inetc\Plugins\x86-unicode"

Var StateFile
Var PowerShell
Var WorkDir
Var LogFile
Var Target
Var PathInput
Var Candidates
Var Dialog
Var Busy
Var Failed
Var Result
Var LanguagePicker
Var DetectionLabel
Var FolderText
Var BrowseButton
Var NextButtonSized
Var NextOriginalX
Var NextOriginalY
Var NextOriginalWidth
Var NextOriginalHeight
Var UiLanguage
!include "..\.cache\RuntimeLanguage.nsh"
CompletedText "$Text_DoneTitle"
DetailsButtonText "$Text_Details"

!define MUI_CUSTOMFUNCTION_ABORT GuardAbort
Page custom TargetPage TargetLeave
!define MUI_PAGE_HEADER_TEXT "$Text_WorkingTitle"
!define MUI_PAGE_HEADER_SUBTEXT "$Text_WorkingSubtitle"
!define MUI_INSTFILESPAGE_FINISHHEADER_TEXT "$Text_DoneTitle"
!define MUI_INSTFILESPAGE_FINISHHEADER_SUBTEXT "$Text_PageSubtitle"
!define MUI_INSTFILESPAGE_ABORTHEADER_TEXT "$Text_FailureTitle"
!define MUI_INSTFILESPAGE_ABORTHEADER_SUBTEXT "$Text_FailureSubtitle"
!define MUI_PAGE_CUSTOMFUNCTION_SHOW ProgressShow
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "$Text_DoneTitle"
!define MUI_FINISHPAGE_TEXT "$Text_DoneText"
!define MUI_FINISHPAGE_BUTTON "$Text_CloseButton"
!define MUI_PAGE_CUSTOMFUNCTION_PRE FinishPre
!define MUI_PAGE_CUSTOMFUNCTION_SHOW FinishShow
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"
MiscButtonText "$Text_BackButton" "$Text_NextButton" "$Text_CancelButton" "$Text_CloseButton"
InstallButtonText "$Text_InstallLabel"


Function .onInit
  System::Call 'kernel32::GetUserDefaultUILanguage() i .r0'
  IntOp $0 $0 & 1023
  ${If} $0 == 4
    StrCpy $LANGUAGE ${LANG_SIMPCHINESE}
  ${Else}
    StrCpy $LANGUAGE ${LANG_ENGLISH}
  ${EndIf}
  ${GetParameters} $0
  ${GetOptions} $0 "/LANG=" $1
  ${If} $1 == ${LANG_ENGLISH}
  ${OrIf} $1 == ${LANG_SIMPCHINESE}
    StrCpy $LANGUAGE $1
  ${EndIf}
  ${GetOptions} $0 "/TARGET=" $Target
  StrCpy $UiLanguage "en"
  ${If} $LANGUAGE == ${LANG_SIMPCHINESE}
    StrCpy $UiLanguage "zh"
  ${EndIf}
  Call LoadLanguage
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "$Text_WindowsRequired"
    Abort
  ${EndIf}
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File "..\.cache\payload\Core.psm1"
  File "..\.cache\payload\Worker.ps1"
  File "..\.cache\7zr.exe"
  File /r "..\licenses"
  StrCpy $StateFile "$PLUGINSDIR\state.ini"
  StrCpy $PowerShell "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  ${If} $LANGUAGE == ${LANG_SIMPCHINESE}
    WriteINIStr "$StateFile" "State" "Locale" "zh"
  ${Else}
    WriteINIStr "$StateFile" "State" "Locale" "en"
  ${EndIf}
  nsExec::ExecToStack '"$PowerShell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\Worker.ps1" -Action Discover -StateFile "$StateFile"'
  Pop $Result
  Pop $0
  ${If} $Result != 0
    MessageBox MB_OK|MB_ICONSTOP "$Text_WorkerFailed$\r$\n$0"
    Abort
  ${EndIf}
  ReadINIStr $WorkDir "$StateFile" "State" "WorkDir"
  ReadINIStr $LogFile "$StateFile" "State" "Log"
FunctionEnd

Function TargetPage
  !insertmacro MUI_HEADER_TEXT "$Text_PageTitle" "$Text_PageSubtitle"
  nsDialogs::Create 1018
  Pop $Dialog
  ${NSD_CreateDropList} 77% 0 23% 60u ""
  Pop $LanguagePicker
  ${NSD_CB_AddString} $LanguagePicker "English"
  ${NSD_CB_AddString} $LanguagePicker "简体中文"
  ${If} $LANGUAGE == ${LANG_SIMPCHINESE}
    SendMessage $LanguagePicker ${CB_SETCURSEL} 1 0
  ${Else}
    SendMessage $LanguagePicker ${CB_SETCURSEL} 0 0
  ${EndIf}
  ${NSD_OnChange} $LanguagePicker LanguageChanged
  ${NSD_CreateLabel} 0 23u 100% 38u "$Text_FolderHelp"
  Pop $FolderText
  ReadINIStr $1 "$StateFile" "State" "Count"
  ${If} $1 > 0
    ${NSD_CreateLabel} 0 66u 100% 12u "$Text_Found"
    Pop $DetectionLabel
    ${NSD_CreateDropList} 0 81u 100% 70u ""
    Pop $Candidates
    StrCpy $2 0
    ${DoWhile} $2 < $1
      ReadINIStr $3 "$StateFile" "State" "Path$2"
      ${NSD_CB_AddString} $Candidates "$3"
      IntOp $2 $2 + 1
    ${Loop}
    SendMessage $Candidates ${CB_SETCURSEL} 0 0
    ${NSD_OnChange} $Candidates CandidateChanged
    ${If} $Target == ""
      ReadINIStr $Target "$StateFile" "State" "Path0"
    ${EndIf}
  ${Else}
    ${NSD_CreateLabel} 0 66u 100% 34u "$Text_Missing"
    Pop $DetectionLabel
  ${EndIf}
  ${NSD_CreateLabel} 0 111u 100% 12u "$Text_FolderLabel"
  Pop $0
  ; Store this handle for immediate language changes without another page.
  WriteINIStr "$StateFile" "State" "FolderLabelHandle" "$0"
  ${NSD_CreateText} 0 127u 79% 14u "$Target"
  Pop $PathInput
  ${NSD_CreateButton} 81% 126u 19% 16u "$Text_Choose"
  Pop $BrowseButton
  ${NSD_OnClick} $BrowseButton BrowseFolder
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_InstallLabel"
  ${If} $NextButtonSized != 1
    ; Widen the primary button in dialog units, keeping its right edge fixed.
    System::Call '*(i 0, i 0, i 30, i 0) p.r1'
    System::Call 'user32::MapDialogRect(p $HWNDPARENT, p r1)'
    System::Call '*$1(i, i, i .r2, i)'
    System::Free $1
    System::Call '*(i 0, i 0, i 0, i 0) p.r1'
    System::Call 'user32::GetWindowRect(p r0, p r1)'
    System::Call 'user32::MapWindowPoints(p 0, p $HWNDPARENT, p r1, i 2)'
    System::Call '*$1(i .r3, i .r4, i .r5, i .r6)'
    System::Free $1
    IntOp $5 $5 - $3
    IntOp $6 $6 - $4
    StrCpy $NextOriginalX $3
    StrCpy $NextOriginalY $4
    StrCpy $NextOriginalWidth $5
    StrCpy $NextOriginalHeight $6
    IntOp $3 $3 - $2
    IntOp $5 $5 + $2
    System::Call 'user32::SetWindowPos(p r0, p 0, i r3, i r4, i r5, i r6, i 4)'
    StrCpy $NextButtonSized 1
  ${EndIf}
  GetDlgItem $0 $HWNDPARENT 2
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_CancelButton"
  nsDialogs::Show
FunctionEnd

Function LanguageChanged
  Pop $0
  SendMessage $LanguagePicker ${CB_GETCURSEL} 0 0 $1
  ${If} $1 == 1
    StrCpy $UiLanguage "zh"
  ${Else}
    StrCpy $UiLanguage "en"
  ${EndIf}
  Call LoadLanguage
  WriteINIStr "$StateFile" "State" "Locale" "$UiLanguage"
  !insertmacro MUI_HEADER_TEXT "$Text_PageTitle" "$Text_PageSubtitle"
  ${NSD_SetText} $FolderText "$Text_FolderHelp"
  ${NSD_SetText} $BrowseButton "$Text_Choose"
  ReadINIStr $0 "$StateFile" "State" "FolderLabelHandle"
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_FolderLabel"
  ReadINIStr $1 "$StateFile" "State" "Count"
  ${If} $1 > 0
    ${NSD_SetText} $DetectionLabel "$Text_Found"
  ${Else}
    ${NSD_SetText} $DetectionLabel "$Text_Missing"
  ${EndIf}
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_InstallLabel"
  GetDlgItem $0 $HWNDPARENT 2
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_CancelButton"
FunctionEnd

Function ProgressShow
  Call RestoreNextButton
  !insertmacro MUI_HEADER_TEXT "$Text_WorkingTitle" "$Text_WorkingSubtitle"
  GetDlgItem $0 $HWNDPARENT 2
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_CancelButton"
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_NextButton"
  GetDlgItem $0 $HWNDPARENT 3
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_BackButton"
  ShowWindow $0 ${SW_HIDE}
FunctionEnd

Function FinishShow
  Call RestoreNextButton
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:$Text_CloseButton"
  GetDlgItem $0 $HWNDPARENT 3
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 2
  ShowWindow $0 ${SW_HIDE}
FunctionEnd

Function RestoreNextButton
  ${If} $NextButtonSized == 1
    GetDlgItem $0 $HWNDPARENT 1
    System::Call 'user32::SetWindowPos(p r0, p 0, i $NextOriginalX, i $NextOriginalY, i $NextOriginalWidth, i $NextOriginalHeight, i 4)'
    StrCpy $NextButtonSized 0
  ${EndIf}
FunctionEnd

Function CandidateChanged
  Pop $0
  ${NSD_GetText} $Candidates $Target
  ${NSD_SetText} $PathInput "$Target"
FunctionEnd

Function BrowseFolder
  Pop $0
  ${NSD_GetText} $PathInput $Target
  nsDialogs::SelectFolderDialog "$Text_BrowseTitle" "$Target"
  Pop $0
  ${If} $0 != error
    ${NSD_SetText} $PathInput "$0"
  ${EndIf}
FunctionEnd

Function TargetLeave
  ${NSD_GetText} $PathInput $Target
  WriteINIStr "$StateFile" "State" "Target" "$Target"
  nsExec::ExecToStack '"$PowerShell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\Worker.ps1" -Action Check -StateFile "$StateFile"'
  Pop $Result
  Pop $0
  ${If} $Result != 0
    Call ShowFailure
    Abort
  ${EndIf}
FunctionEnd

Function ShowFailure
  ReadINIStr $0 "$StateFile" "State" "Message"
  ${If} $0 == ""
    StrCpy $0 "$Text_WorkerFailed"
  ${EndIf}
  MessageBox MB_OK|MB_ICONSTOP "$0$\r$\n$\r$\n$Text_LogHint$\r$\n$LogFile"
FunctionEnd

Section "Resources"
  StrCpy $Busy 1
  DetailPrint "$Text_Downloading"
  download_retry:
  Delete "$WorkDir\ResourcesPack.7z"
  inetc::get /CONNECTTIMEOUT 30 /RECEIVETIMEOUT 60 /NOCOOKIES /USERAGENT "AXE-Resource-Installer/1.0" /HEADER "Cache-Control: no-cache" /TRANSLATE "$Text_DownloadFile" "$Text_Connecting" "$Text_Second" "$Text_Minute" "$Text_Hour" "$Text_Plural" "$Text_DownloadProgress" "$Text_Remaining" /CANCELTEXT "$Text_CancelButton" "https://r2.axekz.com/packages/ResourcesPack.7z" "$WorkDir\ResourcesPack.7z" /END
  Pop $Result
  FileOpen $4 "$LogFile" a
  FileWrite $4 "Download: $Result$\r$\n"
  FileClose $4
  ${If} $Result != "OK"
    ${If} $Result == "Cancelled"
      DetailPrint "$Text_Cancelled"
    ${Else}
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$Text_RetryDownload$\r$\n$Result$\r$\n$Text_LogHint$\r$\n$LogFile" IDRETRY download_retry
    ${EndIf}
    StrCpy $Failed 1
    StrCpy $Busy 0
    SetErrorLevel 1
    Abort
  ${EndIf}
  ; Once copying can begin, allow it to finish or roll back instead of killing the worker.
  GetDlgItem $0 $HWNDPARENT 2
  EnableWindow $0 0
  nsExec::ExecToLog '"$PowerShell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\Worker.ps1" -Action Install -StateFile "$StateFile"'
  Pop $Result
  StrCpy $Busy 0
  EnableWindow $0 1
  ${If} $Result != 0
    StrCpy $Failed 1
    Call ShowFailure
    SetErrorLevel 1
    Abort
  ${EndIf}
SectionEnd

Function FinishPre
  ${If} $Failed == 1
    Abort
  ${EndIf}
FunctionEnd

Function GuardAbort
  ${If} $Busy == 1
    Abort
  ${EndIf}
FunctionEnd

Function .onGUIEnd
  ${If} $WorkDir != ""
    nsExec::ExecToStack '"$PowerShell" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\Worker.ps1" -Action Cleanup -StateFile "$StateFile"'
    Pop $0
    Pop $1
  ${EndIf}
FunctionEnd
