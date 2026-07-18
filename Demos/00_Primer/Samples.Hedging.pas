unit Samples.Hedging;

interface

procedure RunHedgingSample;

implementation

uses
  System.SyncObjs,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Hedging;

procedure RunHedgingSample;
begin
  // Nota: le azioni sottoposte a hedging devono essere idempotenti,
  // perche' i tentativi perdenti continuano a girare in background.
  var LAttemptIndex := 0;

  var LPolicy := THedgingBuilder
    .Handle(ENotImplemented)
    .MaxAttempts(2)
    .Delay(TTimeSpan.FromMilliseconds(500))
    .OnHedging(
      procedure(AContext: THedgingContext)
      begin
        Writeln('Endpoint lento: lancio del tentativo parallelo n. ',
          AContext.AttemptNumber, '...');
      end);

  Writeln('Chiamata a un endpoint lento (il primo tentativo impiega 3 secondi)...');

  LPolicy.Execute(
    procedure
    begin
      // Il tentativo primario e' lento, quello parallelo risponde subito.
      if TInterlocked.Increment(LAttemptIndex) = 1 then
        Sleep(3000)
      else
        Sleep(300);
    end
  );

  Writeln('Risposta ricevuta dal tentativo piu'' veloce!');

  // Attende il tentativo abbandonato prima di terminare la demo.
  Sleep(3000);

  Writeln;
  Writeln('Ora tutti i tentativi falliscono...');

  try
    LPolicy.Execute(
      procedure
      begin
        raise ENotImplemented.Create('Servizio non disponibile');
      end
    );
  except on E: Exception do
    Writeln(E.ClassName, ': ', E.Message);
  end;
end;

end.
