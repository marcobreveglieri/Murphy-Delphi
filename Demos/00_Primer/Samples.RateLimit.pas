unit Samples.RateLimit;

interface

procedure RunRateLimitSample;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  System.TimeSpan,
  System.Rtti,
  Murphy.Policy.RateLimit;

procedure RunRateLimitSample;
begin
  var LPolicy := TRateLimitBuilder
    .Handle(ENotImplemented)
    .Allow(10)
    .Within(TTimeSpan.FromSeconds(1));

  var LCounter := 0;

  while LCounter < 100 do
  begin

    Inc(LCounter);

    try

      LPolicy.Execute(
        procedure
        begin
          Writeln('Attempt no. ', LCounter);
        end
      );

    except on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
    end;

    if LCounter > 50 then
      Sleep(500)
    else
      Sleep(1);
  end;
end;

end.
