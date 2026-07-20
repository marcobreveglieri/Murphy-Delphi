unit Samples.Retry;

interface

procedure RunRetrySample;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Retry;

procedure RunRetrySample;
begin
  var LCounter := 0;
  var LResult := '';

  TRetryBuilder.Handle([EFileNotFoundException])
    .RetryForever()
    .RetryOnce()
    .Retry(5)
    .Wait(TTimeSpan.FromSeconds(2))
    .When(
      function (AContext: TRetryContext): Boolean
      begin
        if AContext.Exception is EAccessViolation then
        begin
          Result := False;
          Exit;
        end;
        AContext.WaitDelay := TTimeSpan.FromSeconds(AContext.Attempts);
        Result := True;
      end)
    .Execute(
      procedure
      begin
        Inc(LCounter);
        Writeln('Attempt no. ', LCounter);
        LResult := TFile.ReadAllText('E:\Temp\Test.txt');
      end
    );

  Writeln('Result: ', LResult);
end;

end.
