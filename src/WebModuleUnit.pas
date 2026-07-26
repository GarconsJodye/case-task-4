unit WebModuleUnit;

interface

uses
  Winapi.Windows,
  Winapi.ActiveX,
  System.SysUtils,
  System.Classes,
  Data.DB,
  Data.Win.ADODB,
  Web.HTTPApp;

type
  TWebModule1 = class(TWebModule)
    procedure DefaultHandlerAction(Sender: TObject; Request: TWebRequest;
      Response: TWebResponse; var Handled: Boolean);
  private
    function HtmlEncode(const Value: string): string;
    function PageHtml(const Title, BodyHtml: string): string;
    function AppUrl(Request: TWebRequest; const Path: string): string;
    procedure AddSecurityHeaders(Response: TWebResponse);
    procedure SendHtml(Response: TWebResponse; const Html: string;
      StatusCode: Integer = 200);
    procedure SendRedirect(Response: TWebResponse; const Location: string);
    procedure ShowList(Request: TWebRequest; Response: TWebResponse);
    procedure ShowNewForm(Request: TWebRequest; Response: TWebResponse);
    procedure CreateRequest(Request: TWebRequest; Response: TWebResponse);
    procedure ShowError(Response: TWebResponse; const MessageText: string;
      StatusCode: Integer);
  end;

var
  WebModuleClass: TComponentClass = TWebModule1;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}
{$R *.dfm}

uses
  DbUnit;

function TWebModule1.HtmlEncode(const Value: string): string;
begin
  Result := Value;
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

function TWebModule1.PageHtml(const Title, BodyHtml: string): string;
begin
  Result :=
    '<!doctype html>' +
    '<html lang="ru">' +
    '<head>' +
    '<meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>' + HtmlEncode(Title) + '</title>' +
    '<style>' +
    'body{font-family:Arial,sans-serif;margin:0;background:#f3f5f7;color:#20242a}' +
    'header{background:#234e70;color:#fff;padding:20px 28px}' +
    'main{max-width:980px;margin:24px auto;background:#fff;padding:24px;border-radius:10px}' +
    'a{color:#174f78}' +
    '.button,button{display:inline-block;background:#234e70;color:#fff;border:0;' +
    'padding:10px 14px;border-radius:6px;text-decoration:none;cursor:pointer}' +
    'table{width:100%;border-collapse:collapse;margin-top:18px}' +
    'th,td{border:1px solid #d8dde3;padding:9px;text-align:left;vertical-align:top}' +
    'th{background:#edf2f6}' +
    'label{display:block;font-weight:bold;margin-top:14px}' +
    'input,select,textarea{width:100%;box-sizing:border-box;padding:9px;margin-top:6px;' +
    'border:1px solid #b9c2ca;border-radius:5px;font:inherit}' +
    'textarea{min-height:110px;resize:vertical}' +
    '.notice{padding:12px;background:#e9f5ec;border-left:4px solid #2f7d42;margin:16px 0}' +
    '.error{padding:12px;background:#fff0f0;border-left:4px solid #a61b1b;margin:16px 0}' +
    '</style>' +
    '</head>' +
    '<body>' +
    '<header><h1>HelpDeskWeb</h1><div>Учёт заявок в IT-службу</div></header>' +
    '<main>' + BodyHtml + '</main>' +
    '</body></html>';
end;

function TWebModule1.AppUrl(Request: TWebRequest; const Path: string): string;
begin
  Result := Request.ScriptName;
  if Path <> '' then
  begin
    if Path[1] <> '/' then
      Result := Result + '/';
  end;
  Result := Result + Path;
end;

procedure TWebModule1.AddSecurityHeaders(Response: TWebResponse);
begin
  Response.SetCustomHeader('Cache-Control', 'no-store');
  Response.SetCustomHeader('X-Content-Type-Options', 'nosniff');
  Response.SetCustomHeader('X-Frame-Options', 'DENY');
  Response.SetCustomHeader('Referrer-Policy', 'no-referrer');
  Response.SetCustomHeader(
    'Content-Security-Policy', 'default-src ''none''; style-src ''unsafe-inline''; ' +
    'form-action ''self''; frame-ancestors ''none''; base-uri ''none''');
end;

procedure TWebModule1.SendHtml(Response: TWebResponse; const Html: string;
  StatusCode: Integer);
var
  Bytes: TBytes;
  Stream: TBytesStream;
begin
  Bytes := TEncoding.UTF8.GetBytes(Html);
  Stream := TBytesStream.Create(Bytes);
  try
    AddSecurityHeaders(Response);
    Response.StatusCode := StatusCode;
    Response.ContentType := 'text/html; charset=utf-8';
    Response.ContentLength := Integer(Stream.Size);
    Response.FreeContentStream := True;
    Response.ContentStream := Stream;
  except
    Stream.Free;
    raise;
  end;
end;

procedure TWebModule1.SendRedirect(Response: TWebResponse;
  const Location: string);
begin
  AddSecurityHeaders(Response);
  Response.StatusCode := 303;
  Response.Location := Location;
  Response.ContentType := 'text/plain; charset=utf-8';
  Response.Content := '';
  Response.ContentLength := 0;
end;

procedure TWebModule1.DefaultHandlerAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  Path: string;
  ComResult: HRESULT;
begin
  Handled := True;
  ComResult := CoInitialize(nil);
  try
    Path := LowerCase(Request.PathInfo);

    try
      if (Path = '') or (Path = '/') then
        ShowList(Request, Response)
      else if Path = '/new' then
        ShowNewForm(Request, Response)
      else if Path = '/create' then
        CreateRequest(Request, Response)
      else
        ShowError(Response, 'Страница не найдена.', 404);
    except
      on E: Exception do
      begin
        Response.LogMessage := E.Message;
        ShowError(Response, 'Внутренняя ошибка сервера.', 500);
      end;
    end;
  finally
    if (ComResult = S_OK) or (ComResult = S_FALSE) then
      CoUninitialize;
  end;
end;

procedure TWebModule1.ShowList(Request: TWebRequest; Response: TWebResponse);
var
  Connection: TADOConnection;
  Query: TADOQuery;
  Body: string;
begin
  Connection := nil;
  Query := nil;
  try
    Connection := CreateConnection;
    Query := TADOQuery.Create(nil);
    Query.Connection := Connection;
    Query.SQL.Text :=
      'SELECT TOP (200) r.RequestID, r.EmployeeName, r.Subject, CONVERT(datetime, r.CreatedAt) AS CreatedAt, ' +
      'd.DepartmentName, s.StatusName ' +
      'FROM dbo.ServiceRequests r ' +
      'INNER JOIN dbo.Departments d ON d.DepartmentID = r.DepartmentID ' +
      'INNER JOIN dbo.RequestStatuses s ON s.StatusID = r.StatusID ' +
      'ORDER BY r.RequestID DESC';
    Query.Open;

    Body :=
      '<h2>Заявки</h2>' +
      '<p><a class="button" href="' + HtmlEncode(AppUrl(Request, '/new')) +
      '">Создать заявку</a></p>' +
      '<p>Показаны последние 200 заявок.</p>';

    if Request.QueryFields.Values['created'] = '1' then
      Body := Body +
        '<div class="notice">Новая заявка успешно добавлена.</div>';

    if Query.IsEmpty then
      Body := Body + '<p>Заявок пока нет.</p>'
    else
    begin
      Body := Body +
        '<table><tr><th>№</th><th>Сотрудник</th><th>Отдел</th>' +
        '<th>Тема</th><th>Статус</th><th>Создана</th></tr>';

      while not Query.Eof do
      begin
        Body := Body +
          '<tr>' +
          '<td>' + Query.FieldByName('RequestID').AsString + '</td>' +
          '<td>' + HtmlEncode(Query.FieldByName('EmployeeName').AsString) + '</td>' +
          '<td>' + HtmlEncode(Query.FieldByName('DepartmentName').AsString) + '</td>' +
          '<td>' + HtmlEncode(Query.FieldByName('Subject').AsString) + '</td>' +
          '<td>' + HtmlEncode(Query.FieldByName('StatusName').AsString) + '</td>' +
          '<td>' + FormatDateTime('dd.mm.yyyy hh:nn', Query.FieldByName('CreatedAt').AsDateTime) + '</td>' +
          '</tr>';
        Query.Next;
      end;

      Body := Body + '</table>';
    end;

    SendHtml(Response, PageHtml('Список заявок', Body));
  finally
    Query.Free;
    Connection.Free;
  end;
end;

procedure TWebModule1.ShowNewForm(Request: TWebRequest;
  Response: TWebResponse);
var
  Connection: TADOConnection;
  Query: TADOQuery;
  Options: string;
  Body: string;
begin
  Connection := nil;
  Query := nil;
  try
    Connection := CreateConnection;
    Query := TADOQuery.Create(nil);
    Query.Connection := Connection;
    Query.SQL.Text :=
      'SELECT DepartmentID, DepartmentName ' +
      'FROM dbo.Departments ORDER BY DepartmentName';
    Query.Open;

    Options := '';
    while not Query.Eof do
    begin
      Options := Options +
        '<option value="' + Query.FieldByName('DepartmentID').AsString + '">' +
        HtmlEncode(Query.FieldByName('DepartmentName').AsString) +
        '</option>';
      Query.Next;
    end;

    Body :=
      '<h2>Новая заявка</h2>' +
      '<p><a href="' + HtmlEncode(AppUrl(Request, '/')) + '">← к списку</a></p>' +
      '<form method="post" accept-charset="utf-8" action="' +
      HtmlEncode(AppUrl(Request, '/create')) + '">' +
      '<label for="employee_name">ФИО сотрудника</label>' +
      '<input id="employee_name" name="employee_name" maxlength="100" required>' +
      '<label for="department_id">Отдел</label>' +
      '<select id="department_id" name="department_id" required>' + Options + '</select>' +
      '<label for="subject">Тема заявки</label>' +
      '<input id="subject" name="subject" maxlength="150" required>' +
      '<label for="description">Описание</label>' +
      '<textarea id="description" name="description" maxlength="1000" required></textarea>' +
      '<p><button type="submit">Сохранить заявку</button></p>' +
      '</form>';

    SendHtml(Response, PageHtml('Новая заявка', Body));
  finally
    Query.Free;
    Connection.Free;
  end;
end;

procedure TWebModule1.CreateRequest(Request: TWebRequest;
  Response: TWebResponse);
var
  DepartmentID: Integer;
  EmployeeName: string;
  SubjectText: string;
  DescriptionText: string;
  Connection: TADOConnection;
  Query: TADOQuery;
begin
  if Request.MethodType <> mtPost then
  begin
    Response.SetCustomHeader('Allow', 'POST');
    ShowError(Response, 'Для создания заявки требуется метод POST.', 405);
    Exit;
  end;

  if Request.ContentLength > 16384 then
  begin
    ShowError(Response, 'Размер запроса превышает допустимые 16 КБ.', 413);
    Exit;
  end;

  DepartmentID := StrToIntDef(Request.ContentFields.Values['department_id'], 0);
  EmployeeName := Trim(Request.ContentFields.Values['employee_name']);
  SubjectText := Trim(Request.ContentFields.Values['subject']);
  DescriptionText := Trim(Request.ContentFields.Values['description']);

  if (DepartmentID <= 0) or (EmployeeName = '') or
     (SubjectText = '') or (DescriptionText = '') then
  begin
    ShowError(Response, 'Заполните все обязательные поля.', 400);
    Exit;
  end;

  if (Length(EmployeeName) > 100) or (Length(SubjectText) > 150) or
     (Length(DescriptionText) > 1000) then
  begin
    ShowError(Response, 'Превышена допустимая длина одного из полей.', 400);
    Exit;
  end;

  Connection := nil;
  Query := nil;
  try
    Connection := CreateConnection;
    Query := TADOQuery.Create(nil);
    Query.Connection := Connection;

    Query.SQL.Text :=
      'SELECT COUNT(*) AS DepartmentCount ' +
      'FROM dbo.Departments WHERE DepartmentID = :DepartmentID';
    Query.Parameters.ParamByName('DepartmentID').DataType := ftInteger;
    Query.Parameters.ParamByName('DepartmentID').Value := DepartmentID;
    Query.Open;
    if Query.FieldByName('DepartmentCount').AsInteger <> 1 then
    begin
      ShowError(Response, 'Выбрано несуществующее подразделение.', 400);
      Exit;
    end;
    Query.Close;

    Query.SQL.Text :=
      'INSERT INTO dbo.ServiceRequests ' +
      '(DepartmentID, StatusID, EmployeeName, Subject, Description) ' +
      'VALUES (:DepartmentID, 1, :EmployeeName, :Subject, :Description)';
    Query.Parameters.ParamByName('DepartmentID').DataType := ftInteger;
    Query.Parameters.ParamByName('EmployeeName').DataType := ftWideString;
    Query.Parameters.ParamByName('EmployeeName').Size := 100;
    Query.Parameters.ParamByName('Subject').DataType := ftWideString;
    Query.Parameters.ParamByName('Subject').Size := 150;
    Query.Parameters.ParamByName('Description').DataType := ftWideString;
    Query.Parameters.ParamByName('Description').Size := 1000;
    Query.Parameters.ParamByName('DepartmentID').Value := DepartmentID;
    Query.Parameters.ParamByName('EmployeeName').Value := EmployeeName;
    Query.Parameters.ParamByName('Subject').Value := SubjectText;
    Query.Parameters.ParamByName('Description').Value := DescriptionText;
    Query.ExecSQL;

    // Post/Redirect/Get не позволяет повторно добавить заявку по F5.
    SendRedirect(Response, AppUrl(Request, '/?created=1'));
  finally
    Query.Free;
    Connection.Free;
  end;
end;

procedure TWebModule1.ShowError(Response: TWebResponse;
  const MessageText: string; StatusCode: Integer);
var
  Body: string;
begin
  Body := '<h2>Ошибка</h2><div class="error">' +
    HtmlEncode(MessageText) + '</div>';
  SendHtml(Response, PageHtml('Ошибка', Body), StatusCode);
end;

end.
