unit DbUnit;

interface

uses
  System.SysUtils,
  Data.Win.ADODB;

function CreateConnection: TADOConnection;

implementation

const
  // Значение подходит для локального учебного стенда SQL Server Express.
  // На сервере задайте HELPDESKWEB_CONNECTION_STRING в окружении пула IIS.
  DEFAULT_CONNECTION_STRING =
    'Provider=MSOLEDBSQL19;' +
    'Data Source=.\SQLEXPRESS;' +
    'Initial Catalog=HelpDeskWebDB;' +
    'Integrated Security=SSPI;' +
    'DataTypeCompatibility=80;' +
    'Use Encryption for Data=Optional;' +
    'TrustServerCertificate=True;';

function GetConnectionString: string;
begin
  Result := Trim(GetEnvironmentVariable('HELPDESKWEB_CONNECTION_STRING'));
  if Result = '' then
    Result := DEFAULT_CONNECTION_STRING;
end;

function CreateConnection: TADOConnection;
begin
  Result := TADOConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.ConnectionTimeout := 10;
    Result.CommandTimeout := 30;
    Result.ConnectionString := GetConnectionString;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

end.
