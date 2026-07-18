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
        Writeln('...calcolo del valore in corso (operazione costosa)...');
        Sleep(300);
        Result := 'valore calcolato alle ' + FormatDateTime('hh:nn:ss.zzz', Now);
      end
    );
    Writeln('Chiamata n. ', LCallIndex, ': ', LResult);
    Sleep(800);
  end;

  // Quando il refresh fallisce con un'eccezione gestita,
  // viene restituito l'ultimo valore valido in cache.
  Writeln;
  Writeln('Refresh fallito: viene servito il valore in cache...');
  Sleep(2500);
  var LStaleResult := LPolicy.Execute(
    function: string
    begin
      raise ENotImplemented.Create('Servizio non disponibile');
    end
  );
  Writeln('Valore stantio: ', LStaleResult);
end;

end.
