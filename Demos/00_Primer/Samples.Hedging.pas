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
  // Note: actions subject to hedging must be idempotent,
  // because the losing attempts keep running in the background.
  var LAttemptIndex := 0;

  var LPolicy := THedgingBuilder
    .Handle(ENotImplemented)
    .MaxAttempts(2)
    .Delay(TTimeSpan.FromMilliseconds(500))
    .OnHedging(
      procedure(AContext: THedgingContext)
      begin
        Writeln('Slow endpoint: launching parallel attempt no. ',
          AContext.AttemptNumber, '...');
      end);

  Writeln('Calling a slow endpoint (the first attempt takes 3 seconds)...');

  LPolicy.Execute(
    procedure
    begin
      // The primary attempt is slow, the parallel one responds right away.
      if TInterlocked.Increment(LAttemptIndex) = 1 then
        Sleep(3000)
      else
        Sleep(300);
    end
  );

  Writeln('Response received from the fastest attempt!');

  // Waits for the abandoned attempt before ending the demo.
  Sleep(3000);

  Writeln;
  Writeln('Now all attempts fail...');

  try
    LPolicy.Execute(
      procedure
      begin
        raise ENotImplemented.Create('Service unavailable');
      end
    );
  except on E: Exception do
    Writeln(E.ClassName, ': ', E.Message);
  end;
end;

end.
