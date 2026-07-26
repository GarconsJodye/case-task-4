library HelpDeskWeb;

uses
  Web.WebBroker,
  Web.Win.ISAPIApp,
  WebModuleUnit in 'WebModuleUnit.pas' {WebModule1: TWebModule},
  DbUnit in 'DbUnit.pas';

{$R *.res}

exports
  GetExtensionVersion,
  HttpExtensionProc,
  TerminateExtension;

begin
  Application.Initialize;
  Application.WebModuleClass := WebModuleClass;
  Application.Run;
end.
