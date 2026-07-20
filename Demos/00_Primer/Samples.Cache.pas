unit Samples.Cache;

interface

procedure RunCacheSample;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Cache;

procedure RunCacheSample;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle(ENotImplemented)
    .Expire(TTimeSpan.FromSeconds(2));

  for var LCallIndex := 1 to 6 do
  begin
    var LResult := LPolicy.Execute(
      function: string
      begin
        Writeln('...computing the value (expensive operation)...');
        Sleep(300);
        Result := 'value computed at ' + FormatDateTime('hh:nn:ss.zzz', Now);
      end
    );
    Writeln('Call no. ', LCallIndex, ': ', LResult);
    Sleep(800);
  end;

  // When the refresh fails with a handled exception,
  // the last valid cached value is returned.
  Writeln;
  Writeln('Refresh failed: serving the cached value...');
  Sleep(2500);
  var LStaleResult := LPolicy.Execute(
    function: string
    begin
      raise ENotImplemented.Create('Service unavailable');
    end
  );
  Writeln('Stale value: ', LStaleResult);
end;

end.
