unit Samples.PolicyWrap;

interface

procedure RunPolicyWrapSample;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Retry,
  Murphy.Policy.Timeout,
  Murphy.Policy.Wrap;

procedure RunPolicyWrapSample;
begin
  // Combina Retry (esterno) e Timeout (interno): ogni tentativo ha
  // un proprio timeout e i tentativi scaduti vengono ritentati.
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(ETimeoutRejectedException)
      .Retry(3)
      .Wait(TTimeSpan.FromMilliseconds(500)),
    TTimeoutBuilder
      .Handle([])
      .After(TTimeSpan.FromSeconds(1))
  ]);

  var LAttempts := 0;

  try
    LWrap.Execute(
      procedure
      begin
        Inc(LAttempts);
        Writeln('Chiamata al database... (tentativo n. ', LAttempts, ')');
        // I primi due tentativi superano il timeout di 1 secondo.
        if LAttempts <= 2 then
          Sleep(2000);
        Writeln('Chiamata completata con successo!');
      end
    );
  except on E: Exception do
    Writeln(E.ClassName, ': ', E.Message);
  end;
end;

end.
