unit Unit1;

interface

{EasyNotes https://github.com/r57zone/EasyNotes}

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, OleCtrls, ExtCtrls, StdCtrls, SQLite3, SQLiteTable3, SHDocVw, ActiveX,
  DateUtils, IniFiles, IdBaseComponent, IdComponent, IdTCPServer,
  IdCustomHTTPServer, IdHTTPServer, XMLDoc, XMLIntf, Registry, Menus, ClipBrd;

type
  TMain = class(TForm)
    WebView: TWebBrowser;
    IdHTTPServer: TIdHTTPServer;
    PopupMenu: TPopupMenu;
    PasteBtn: TMenuItem;
    CutBtn: TMenuItem;
    CopyBtn: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure WebViewBeforeNavigate2(Sender: TObject;
      const pDisp: IDispatch; var URL, Flags, TargetFrameName, PostData,
      Headers: OleVariant; var Cancel: WordBool);
    procedure WebViewDocumentComplete(Sender: TObject;
      const pDisp: IDispatch; var URL: OleVariant);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormActivate(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
    procedure IdHTTPServerCommandGet(AThread: TIdPeerThread;
      ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
    procedure PasteBtnClick(Sender: TObject);
    procedure CopyBtnClick(Sender: TObject);
    procedure CutBtnClick(Sender: TObject);
  private
    procedure LoadNotes;
    procedure NewNote(MemoFocus: boolean);
    procedure NoteDone(e: integer);
    procedure MessageHandler(var Msg: TMsg; var Handled: Boolean);
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Main: TMain;
  CloseDuplicate: boolean;
  SQLDB: TSQLiteDatabase;
  NoteIndex:int64; LatestNote: string;
  FOleInPlaceActiveObject: IOleInPlaceActiveObject;
  SaveMessageHandler: TMessageEvent;
  ID_NEW_NOTE, ID_NOTES, ID_TODAY, ID_YESTERDAY, ID_DAYSAGO, ID_SYNC: string;
  ID_CUT, ID_COPY, ID_PASTE, IDS_LAST_UPDATE: string;
  AllowIPs: TStringList;

implementation

{$R *.dfm}

//TimeStamp �� �������� GMT ��� UTC+0
function GetTimeStamp: int64;
var
 SystemTime: TSystemTime;
begin
  GetSystemTime(SystemTime);
  with SystemTime do
    Result:=DateTimeToUNIX(EncodeDate(wYear, wMonth, wDay) + EncodeTime(wHour, wMinute, wSecond, wMilliseconds));
end;

function StrToCharCodes(Str: string): string;
var
  i: integer;
begin
  Result:='';
  for i:=1 to Length(Str) do
    Result:=Result + 'x' + IntToStr( Ord( Str[i] ) );
end;

function CharCodesToStr(Str: string): string;
var
  i: integer;
begin
  Result:='';
  if Length(Str) = 0 then Exit;
  if Str[1] <> 'x' then Exit;
  Delete(Str, 1, 1);
  Str:=Str + 'x';
  while Pos('x', Str) > 0 do begin
    Result:=Result + Chr( StrToIntDef ( Copy( Str, 1, Pos('x', Str) - 1), 0 ) );
    Delete(Str, 1, Pos('x', Str));
  end;
end;

function StringToWideString(const s: AnsiString; codePage: Word): WideString;
var
  l: integer;
begin
  if s = '' then
    Result:=''
  else
  begin
    l:=MultiByteToWideChar(codePage, MB_PRECOMPOSED, PChar(@s[1]), -1, nil, 0);
    SetLength(Result, l - 1);
    if l > 1 then
      MultiByteToWideChar(CodePage, MB_PRECOMPOSED, PChar(@s[1]), -1, PWideChar(@Result[1]), l - 1);
  end;
end;

function StrToWideCharCodes(Str: string): string;
var
  i: integer;
  WStr: WideString;
begin
  Result:='';
  WStr:=StringToWideString(Str, CP_ACP);
  for i:=1 to Length(WStr) do
    Result:=Result + 'x' + IntToStr( Ord( WStr[i] ) );
end;

function WideCharCodesToStr(Str: string): string;
var
  i: integer;
begin
  Result:='';
  if Length(Str) = 0 then Exit;
  if Str[1] <> 'x' then Exit;
  Delete(Str, 1, 1);
  Str:=Str + 'x';
  while Pos('x', Str) > 0 do begin
    Result:=Result + WideChar( StrToIntDef ( Copy( Str, 1, Pos('x', Str) - 1), 0 ) );
    Delete(Str, 1, Pos('x', Str));
  end;
end;

function GetLocaleInformation(Flag: Integer): string;
var
  pcLCA: array [0..20] of Char;
begin
  if GetLocaleInfo(LOCALE_SYSTEM_DEFAULT, Flag, pcLCA, 19)<=0 then
    pcLCA[0]:=#0;
  Result:=pcLCA;
end;

procedure TMain.FormCreate(Sender: TObject);
var
  Ini: TIniFile;
  Reg: TRegistry;
  WND: HWND;
begin
  //�������������� ��������� �������
  WND:=FindWindow('TMain', 'EasyNotes');
  if WND <> 0 then begin
    SetForegroundWindow(WND);
    Halt;
  end;
  Caption:='EasyNotes';

  Ini:=TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'Config.ini');
  IdHTTPServer.DefaultPort:=Ini.ReadInteger('Main', 'Port', 735);
  Width:=Ini.ReadInteger('Main', 'Width', Width);
  Height:=Ini.ReadInteger('Main', 'Height', Height);
  if Ini.ReadBool('Main', 'FirstRun', true) then begin
    Ini.WriteInteger('Main', 'Port', 735);
    Ini.WriteBool('Main', 'FirstRun', false);
    Reg:=TRegistry.Create;
    Reg.RootKey:=HKEY_CURRENT_USER;
    if Reg.OpenKey('\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION', true) then begin
        Reg.WriteInteger(ExtractFileName(ParamStr(0)), 11000);
      Reg.CloseKey;
    end;
    Reg.Free;
  end;
  Ini.Free;

  IdHTTPServer.Active:=true;
  if GetLocaleInformation(LOCALE_SENGLANGUAGE) = 'Russian' then begin
    ID_NEW_NOTE:='����� �������';
    ID_NOTES:='�������';
    ID_TODAY:='�������';
    ID_YESTERDAY:='�����';
    ID_DAYSAGO:='��. �����';
    ID_SYNC:='�������������';
    ID_CUT:='��������';
    ID_COPY:='����������';
    ID_PASTE:='��������';
    IDS_LAST_UPDATE:='��������� ����������:';
  end else begin
    ID_NEW_NOTE:='New note';
    ID_NOTES:='Notes';
    ID_TODAY:='Today';
    ID_YESTERDAY:='Yesterday';
    ID_DAYSAGO:='days ago';
    ID_SYNC:='Sync';
    ID_CUT:='Cut';
    ID_COPY:='Copy';
    ID_PASTE:='Paste';
    IDS_LAST_UPDATE:='Last update:';
  end;
  CutBtn.Caption:=ID_CUT;
  CopyBtn.Caption:=ID_COPY;
  PasteBtn.Caption:=ID_PASTE;
  Application.Title:=Caption;
  Main.Visible:=false;
  WebView.Silent:=true;
  WebView.Navigate(ExtractFilePath(ParamStr(0)) + 'main.html');
  SQLDB:=TSQLiteDatabase.Create('Notes.db');
  if not SQLDB.TableExists('notes') then
    SQLDB.ExecSQL('CREATE TABLE Notes (ID TIMESTAMP, Note TEXT, DateTime TIMESTAMP)');

  //����������� IP ������� �������
  AllowIPs:=TStringList.Create;
  AllowIPs.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'Allow.txt');
end;

function ExtractTitle(Str: string): string;
begin
  if Pos(#10, Str) > 0 then
    Str:=Copy(Str, 1, Pos(#10, Str) - 1);
  if Length(Str) > 150 then
    Str:=Copy(Str, 1, 150);
  Result:=Str;
end;

function NoteDateTime(sDate: string): string; //��� "�����" � "�������"
var
  mTime, nYear: string;
begin
  sDate:=DateTimeToStr(UNIXToDateTime(StrToInt64(sDate))); //������� TimeStamp � DateTimeStr

  mTime:=Copy(sDate, Pos(' ', sDate) + 1, Length(sDate) - Pos(' ', sDate));
  nYear:=FormatDateTime('yyyy', StrToDate(Copy(sDate, 1, Pos(' ', sDate))));

  if nYear = FormatDateTime('yyyy', Date) then
    Result:=FormatDateTime('d mmm.', StrToDate(Copy(sDate, 1, Pos(' ', sDate)))) + ' ' + Copy(mTime, 1, Length(mTime) - 3)
  else
    Result:=FormatDateTime('d.mm.yyyy', StrToDate(Copy(sDate, 1, Pos(' ', sDate)))) + ' ' + Copy(mTime, 1, Length(mTime) - 3);
end;

function ListDateTime(sDate: string): string;
var
  mTime, MyDate, nYear: string; DaysAgo: integer;
begin
  sDate:=DateTimeToStr(UNIXToDateTime(StrToInt64(sDate))); //������� TimeStamp � DateTimeStr

  DaysAgo:=DaysBetween(StrToDate(Copy(sDate, 1, Pos(' ', sDate) - 1)), Date);

  mTime:=Copy(sDate, Pos(' ', sDate) + 1, Length(sDate) - Pos(' ', sDate));

  MyDate:=FormatDateTime('d mmm.', StrToDate(Copy(sDate, 1, Pos(' ', sDate))));

  if DaysAgo < DayOfTheWeek(Date) then begin
    MyDate:=FormatDateTime('dddd', StrToDate(Copy(sDate, 1, Pos(' ', sDate))));
    MyDate[1]:=AnsiUpperCase(MyDate[1])[1];
  end;

  if DaysAgo = 0 then MyDate:=Copy(mTime, 1, Length(mTime) - 3);
  if DaysAgo = 1 then MyDate:=ID_YESTERDAY;

  nYear:=FormatDateTime('yyyy', StrToDate(Copy(sDate, 1, Pos(' ', sDate))));
  if nYear <> FormatDateTime('yyyy', Date) then
    MyDate:=FormatDateTime('d mmm. yyyy', StrToDate(Copy(sDate, 1, Pos(' ', sDate))));

  Result:=MyDate;
end;

procedure TMain.LoadNotes;
var
  i: integer; SQLTB: TSQLiteTable;
begin
  SQLTB:=SQLDB.GetTable('SELECT * FROM Notes ORDER BY DateTime DESC');
  try
    WebView.OleObject.Document.getElementById('NotesCount').innerHTML:=ID_NOTES + ' (' + IntToStr(SQLTB.Count) + ')';
    WebView.OleObject.Document.getElementById('items').innerHTML:='';
    for i:=0 to SQLTB.Count - 1 do begin
      WebView.OleObject.Document.getElementById('items').innerHTML:=WebView.OleObject.Document.getElementById('items').innerHTML +
      '<div onclick="document.location=''#note' + SQLTB.FieldAsString(0) + ''';" id="note"><div id="title">' + ExtractTitle(CharCodesToStr(SQLTB.FieldAsString(1))) + '</div><div id="date">' + ListDateTime(SQLTB.FieldAsString(2))  + '</div></div>';
      SQLTB.Next;
    end;
  finally
    SQLTB.Free;
  end;
end;

procedure TMain.NoteDone(e: integer);
var
  CurTimeStamp: int64;
begin
  //Add
  if (NoteIndex = -1) and (Trim(WebView.OleObject.Document.getElementById('memo').innerHTML) <> '') then begin
	  CurTimeStamp:=GetTimeStamp;
	  SQLDB.ExecSQL('INSERT INTO Notes (ID, Note, DateTime) values("' + IntToStr(CurTimeStamp) + '", "' + StrToCharCodes(WebView.OleObject.Document.getElementById('memo').innerHTML)+'", "' + IntToStr(DateTimeToUnix(Now)) + '")');
	  NoteIndex:=CurTimeStamp; //��� ����, ����� ��������� ������ �� ����������� ����� � �����
	  if e = 0 then begin
      LoadNotes;
      NewNote(true); //����� �������
    end;
  end;

  //Update
  if (NoteIndex <> -1) and (Trim(LatestNote) <> Trim(WebView.OleObject.Document.getElementById('memo').innerHTML)) then
	  SQLDB.ExecSQL('UPDATE Notes SET Note="' + StrToCharCodes(WebView.OleObject.Document.getElementById('memo').innerHTML) + '", DateTime="' + IntToStr(DateTimeToUnix(Now)) + '" WHERE ID=' + IntToStr(NoteIndex));
	  if e = 0 then begin
      LoadNotes;
      NewNote(true);
    end;
end;

procedure TMain.WebViewBeforeNavigate2(Sender: TObject;
  const pDisp: IDispatch; var URL, Flags, TargetFrameName, PostData,
  Headers: OleVariant; var Cancel: WordBool);
var
  sUrl: string;
  i, DaysAgo: integer;
  NoteDate, sDate: string;
  SQLTB: TSQLiteTable;
begin
  sUrl:=ExtractFileName(StringReplace(Url, '/', '\', [rfReplaceAll]));

  if Pos('main.html', sUrl) = 0 then Cancel:=true;

  if Pos('main.html#note', sUrl) > 0 then begin
    Delete(sUrl, 1, Pos('#note', sUrl) + 4);
    NoteIndex:=StrToIntDef(sUrl, 0);
    SQLTB:=SQLDB.GetTable('SELECT ID, Note, DateTime FROM NOTES WHERE ID=' + sURL);

    WebView.OleObject.Document.getElementById('NoteTitle').innerHTML:=ExtractTitle(CharCodesToStr(SQLTB.FieldAsString(1)));
    LatestNote:=CharCodesToStr(SQLTB.FieldAsString(1));

    sDate:=DateTimeToStr(UNIXToDateTime(StrToInt64(SQLTB.FieldAsString(2)))); //������� TimeStamp � DateTimeStr
    NoteDate:=Copy(sDate, 1, Pos(' ', sDate) - 1);
    DaysAgo:=DaysBetween(StrToDate(NoteDate), Date);

    if ID_DAYSAGO='��. �����' then begin

      if IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '1' then NoteDate:=IntToStr(DaysAgo) + ' ���� �����';
    
      if (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '2') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '3') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '4') then NoteDate:=IntToStr(DaysAgo) + ' ��� �����';

      if (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))]= '5') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '6') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '7') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '8') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '9') or
      (IntToStr(DaysAgo)[Length(IntToStr(DaysAgo))] = '0') then NoteDate:=IntToStr(DaysAgo) + ' ���� �����';
    end else
      NoteDate:=IntToStr(DaysAgo) + ' ' + ID_DAYSAGO;

    if DaysAgo = 0 then NoteDate:=ID_TODAY;
    if DaysAgo = 1 then NoteDate:=ID_YESTERDAY;

    WebView.OleObject.Document.getElementById('DaysAgo').innerHTML:=NoteDate;
    WebView.OleObject.Document.getElementById('DateNote').innerHTML:=NoteDateTime(SQLTB.FieldAsString(2));
    WebView.OleObject.Document.getElementById('memo').innerHTML:=CharCodesToStr(SQLTB.FieldAsString(1));

  end;

  if sUrl = 'main.html#new' then
    NewNote(true);

  if sUrl = 'main.html#done' then
    NoteDone(0); //���������, ���������, ������ "0" ��������� ������ ������� � ����������

  //�������
  if (sUrl = 'main.html#rem') and (NoteIndex <> -1) then begin
    WebView.OleObject.Document.getElementById('memo').innerHTML:='';
    SQLDB.ExecSQL('DELETE FROM Notes WHERE ID=' + IntToStr(NoteIndex));
    LoadNotes;
    NewNote(false);
  end;

  if (sUrl = 'main.html#memo-menu') then begin
    PasteBtn.Enabled:=Clipboard.AsText <> '';
    CutBtn.Enabled:=WebView.OleObject.Document.getElementById('memo').selectionStart <> WebView.OleObject.Document.getElementById('memo').selectionEnd;
    CopyBtn.Enabled:=CutBtn.Enabled;
    PopupMenu.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
  end;

  if (sUrl = 'main.html#about') then
    Application.MessageBox(PChar(Caption + ' 0.8.3' + #13#10 +
    IDS_LAST_UPDATE + ' 18.07.19' + #13#10 +
    'https://r57zone.github.io' + #13#10 +
    'r57zone@gmail.com'), PChar(Caption), MB_ICONINFORMATION);
end;

procedure TMain.WebViewDocumentComplete(Sender: TObject;
  const pDisp: IDispatch; var URL: OleVariant);
var
  sUrl: string;
begin
  sUrl:=ExtractFileName(StringReplace(Url, '/', '\', [rfReplaceAll]));
  if pDisp=(Sender as TWebBrowser).Application then
    if sUrl = 'main.html' then begin
      Main.Visible:=true;
      LoadNotes;
      NewNote(true);
    end;
end;

procedure TMain.FormClose(Sender: TObject; var Action: TCloseAction);
var
  Ini: TIniFile;
begin
  if Main.WindowState <> wsMaximized then begin
    Ini:=TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'Config.ini');
    Ini.WriteInteger('Main', 'Width', Width);
    Ini.WriteInteger('Main', 'Height', Height);
    Ini.Free;
  end;
  IdHTTPServer.Active:=false;

  //���������, ���������, ������ "-1" �� ��������� ������ ������� � ����������
  NoteDone(-1);

  SQLDB.Free;
  Application.OnMessage:=SaveMessageHandler;
  FOleInPlaceActiveObject:=nil;
  AllowIPs.Free;
end;

procedure TMain.MessageHandler(var Msg: TMsg; var Handled: Boolean);
var
  iOIPAO: IOleInPlaceActiveObject;
  Dispatch: IDispatch;
begin
  if not Assigned(WebView) then begin
    Handled := False;
    Exit;
  end;
  Handled := (IsDialogMessage(WebView.Handle, Msg) = True);
  if (Handled) and (not WebView.Busy) then
  begin
    if FOleInPlaceActiveObject = nil then
    begin
      Dispatch := WebView.Application;
      if Dispatch <> nil then
      begin
        Dispatch.QueryInterface(IOleInPlaceActiveObject, iOIPAO);
        if iOIPAO <> nil then
          FOleInPlaceActiveObject:=iOIPAO;
      end;
    end;
    if FOleInPlaceActiveObject <> nil then
      if ((Msg.message = WM_KEYDOWN) or (Msg.message = WM_KEYUP)) and
        ((Msg.wParam = VK_BACK) or (Msg.wParam = VK_LEFT) or (Msg.wParam = VK_RIGHT)
        or (Msg.wParam = VK_UP) or (Msg.wParam = VK_DOWN)) then exit;
        FOleInPlaceActiveObject.TranslateAccelerator(Msg);
  end;
end;

procedure TMain.FormActivate(Sender: TObject);
begin
  SaveMessageHandler:=Application.OnMessage;
  Application.OnMessage:=MessageHandler;
end;

procedure TMain.FormDeactivate(Sender: TObject);
begin
  Application.OnMessage:=SaveMessageHandler;
end;

procedure TMain.NewNote(MemoFocus: boolean);
begin
  WebView.OleObject.Document.getElementById('NoteTitle').innerHTML:=ID_NEW_NOTE;
  WebView.OleObject.Document.getElementById('DaysAgo').innerHTML:=ID_TODAY;
  WebView.OleObject.Document.getElementById('DateNote').innerHTML:=FormatDateTime('d mmm. h:nn', Now);
  WebView.OleObject.Document.getElementById('memo').innerHTML:='';
  if MemoFocus then
    WebView.OleObject.Document.getElementById('memo').focus;
  NoteIndex:=-1;
  LatestNote:='';
end;

procedure TMain.IdHTTPServerCommandGet(AThread: TIdPeerThread;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  i: integer; SQLTB: TSQLiteTable; NotesIDs: TStringList;
  XMLDoc: IXMLDocument;
  XMLNode: IXMLNode;
  RequestDocument: string;
begin
  CoInitialize(nil);

  if (AllowIPs.Count > 0) and (Trim(AnsiUpperCase(AllowIPs.Strings[0])) <> 'ALL') then
    if Pos(AThread.Connection.Socket.Binding.PeerIP, AllowIPs.Text) = 0 then Exit;

  if ARequestInfo.Document = '/api/getnotes' then begin

    SQLTB:=SQLDB.GetTable('SELECT * FROM Notes ORDER BY DateTime DESC');
    try
      AResponseInfo.ContentText:='<notes>' + #13#10;
      for i:=0 to SQLTB.Count - 1 do begin
        AResponseInfo.ContentText:=AResponseInfo.ContentText + #9 + '<note id="' + SQLTB.FieldAsString(0) + '" datetime="' + AnsiToUTF8(SQLTB.FieldAsString(2)) + '"></note>' + #13#10;
        SQLTB.Next;
      end;
    finally
      AResponseInfo.ContentText:=AResponseInfo.ContentText + '</notes>';
      SQLTB.Free;
    end;

    RequestDocument:='none';
  end;

  if ARequestInfo.Document = '/api/getfullnotes' then begin

    SQLTB:=SQLDB.GetTable('SELECT * FROM Notes ORDER BY DateTime DESC');
    try
      AResponseInfo.ContentText:='<notes>' + #13#10;
      for i:=0 to SQLTB.Count - 1 do begin
        AResponseInfo.ContentText:=AResponseInfo.ContentText + #9 + '<note id="' + SQLTB.FieldAsString(0) + '" datetime="' + SQLTB.FieldAsString(2) + '">' + StrToWideCharCodes(CharCodesToStr(SQLTB.FieldAsString(1))) + '</note>' + #13#10;
        SQLTB.Next;
      end;
    finally
      AResponseInfo.ContentText:=AResponseInfo.ContentText + '</notes>';
      SQLTB.Free;
    end;

    RequestDocument:='none';
  end;

  if Copy(ARequestInfo.Document, 1, 9)= '/api/getnote=' then begin
    NotesIDs:=TStringList.Create;
    NotesIDs.Text:=Copy(ARequestInfo.Document, 10, Length(ARequestInfo.Document));
    NotesIDs.Text:=StringReplace(NotesIDs.Text, ',', #13#10, [rfReplaceAll]);

    AResponseInfo.ContentText:='<notes>' + #13#10;
    for i:=0 to NotesIDs.Count - 1 do
      if Trim(NotesIDs.Strings[i]) <> '' then begin
        SQLTB:=SQLDB.GetTable('SELECT ID, Note, DateTime FROM NOTES WHERE ID=' + NotesIDs.Strings[i]);
        try
          AResponseInfo.ContentText:=AResponseInfo.ContentText + #9 + '<note id="' + SQLTB.FieldAsString(0) + '" datetime="' + SQLTB.FieldAsString(2) + '">' + StrToWideCharCodes(AnsiToUTF8(CharCodesToStr(SQLTB.FieldAsString(1)))) + '</note>' + #13#10;
        finally
          SQLTB.Free;
        end;
      end;

    AResponseInfo.ContentText:=AResponseInfo.ContentText + '</notes>';
    NotesIDs.Free;
    RequestDocument:='none';
  end;

  if (ARequestInfo.Document = '/api/syncnotes') and (ARequestInfo.Command = 'POST') and (Trim(ARequestInfo.FormParams) <> '') then begin
    //NoteDone(1); //���������� ������� �������, ��� ���������� ������
    Caption:='EasyNotes - ' + ID_SYNC;
    Application.Title:=Caption;
    XMLDoc:=TXMLDocument.Create(nil);
    try
      XMLDoc:=LoadXMLData(ARequestInfo.FormParams);
      XMLDoc.Active:=true;
      AResponseInfo.ContentText:='ok';
    except;
      AResponseInfo.ContentText:='error';
    end;

    XMLNode:=XMLDoc.DocumentElement;
    for i:=0 to XMLNode.ChildNodes.Count - 1 do
      try
        if (XMLNode.ChildNodes[i].NodeName = 'insert') and (Trim( StrToCharCodes( WideCharCodesToStr(XMLNode.ChildNodes[i].NodeValue) ) ) <> '') then
          SQLDB.ExecSQL('INSERT INTO Notes (ID, Note, DateTime) values("' + XMLNode.ChildNodes[i].Attributes['id'] + '", "' + StrToCharCodes(WideCharCodesToStr(XMLNode.ChildNodes[i].NodeValue)) + '", "' + XMLNode.ChildNodes[i].Attributes['datetime'] + '")');

        if XMLNode.ChildNodes[i].NodeName = 'update' then
          SQLDB.ExecSQL('UPDATE Notes SET Note="' + StrToCharCodes(WideCharCodesToStr(XMLNode.ChildNodes[i].NodeValue)) + '", DateTime="' + XMLNode.ChildNodes[i].Attributes['datetime'] + '" WHERE ID=' + XMLNode.ChildNodes[i].Attributes['id']);

        if XMLNode.ChildNodes[i].NodeName = 'delete' then
          SQLDB.ExecSQL('DELETE FROM Notes WHERE ID=' + XMLNode.ChildNodes[i].Attributes['id']);
      except
      end;

    //�������� � ���������� �������, ������� ������ ��������� �������� � LoadNotes ����������� �����.
    WebView.Navigate(ExtractFilePath(ParamStr(0)) + 'main.html');

    Caption:='EasyNotes';
    Application.Title:=Caption;
    XMLDoc.Active:=false;
    RequestDocument:='none';
  end;

  if (RequestDocument <> 'none') then begin
    RequestDocument:=ExtractFilePath(ParamStr(0)) + '\webapp' + StringReplace(ARequestInfo.Document, '/', '\', [rfReplaceAll]);
    RequestDocument:=StringReplace(RequestDocument, '\\', '\', [rfReplaceAll]);

    if ARequestInfo.Document = '/webapp' then //�� webapp ������ ������� ����
      RequestDocument:=ExtractFilePath(ParamStr(0)) + 'webapp\main.html';

    if FileExists(RequestDocument) then begin
      AResponseInfo.ContentType:=IdHTTPServer.MIMETable.GetDefaultFileExt(RequestDocument);

    if ARequestInfo.Document = '/app.manifest' then
      AResponseInfo.ContentType:='text/cache-manifest';

      IdHTTPServer.ServeFile(AThread, AResponseinfo, RequestDocument);
    end else
      AResponseInfo.ContentText:='error';
  end;

  CoUninitialize;
end;

procedure TMain.PasteBtnClick(Sender: TObject);
begin
  keybd_event(VK_CONTROL, MapVirtualKey(VK_CONTROL, 0), 0, 0);
  keybd_event(Ord('V'), MapVirtualKey(Ord('V'), 0), 0, 0);
  keybd_event(Ord('V'), MapVirtualKey(Ord('V'), 0), KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, MapVirtualKey(VK_CONTROL, 0), KEYEVENTF_KEYUP, 0)
end;

procedure TMain.CopyBtnClick(Sender: TObject);
begin
  keybd_event(VK_CONTROL, MapVirtualKey(VK_CONTROL, 0), 0, 0);
  keybd_event(Ord('C'), MapVirtualKey(Ord('C'), 0), 0, 0);
  keybd_event(Ord('C'), MapVirtualKey(Ord('C'), 0), KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, MapVirtualKey(VK_CONTROL, 0), KEYEVENTF_KEYUP, 0)
end;

procedure TMain.CutBtnClick(Sender: TObject);
begin
  keybd_event(VK_CONTROL, MapVirtualKey(VK_CONTROL, 0), 0, 0);
  keybd_event(Ord('X'), MapVirtualKey(Ord('X'), 0), 0, 0);
  keybd_event(Ord('X'), MapVirtualKey(Ord('X'), 0), KEYEVENTF_KEYUP, 0);
  keybd_event(VK_CONTROL, MapVirtualKey(VK_CONTROL, 0), KEYEVENTF_KEYUP, 0)
end;

initialization
 OleInitialize(nil);

finalization
 OleUninitialize;

end.
