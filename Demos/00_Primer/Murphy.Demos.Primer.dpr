program Murphy.Demos.Primer;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Samples.Retry in 'Samples.Retry.pas',
  Samples.CircuitBreaker in 'Samples.CircuitBreaker.pas',
  Samples.Fallback in 'Samples.Fallback.pas',
  Samples.RateLimit in 'Samples.RateLimit.pas',
  Samples.Timeout in 'Samples.Timeout.pas',
  Samples.Bulkhead in 'Samples.Bulkhead.pas',
  Samples.Cache in 'Samples.Cache.pas',
  Samples.Hedging in 'Samples.Hedging.pas',
  Samples.PolicyWrap in 'Samples.PolicyWrap.pas';

begin
  ReportMemoryLeaksOnShutdown := True;

  try

    while True do
    begin
      Writeln('--------------------');
      Writeln('B) Bulkhead');
      Writeln('A) Cache');
      Writeln('C) Circuit Breaker');
      Writeln('F) Fallback');
      Writeln('H) Hedging');
      Writeln('W) Policy Wrap');
      Writeln('L) Rate Limit');
      Writeln('R) Retry');
      Writeln('T) Timeout');
      Writeln('             Q) quit');
      Writeln('--------------------');
      Writeln;

      var LInput: string;
      Readln(LInput);

      var LCommand := UpperCase(LInput);

      if Length(LCommand) <= 0 then
        Continue;

      if LCommand = 'Q' then
        Break;

      Writeln;
      Writeln;

      case LCommand.Chars[0] of
        'A': RunCacheSample;
        'B': RunBulkheadSample;
        'C': RunCircuitBreakerSample;
        'F': RunFallbackSample;
        'H': RunHedgingSample;
        'L': RunRateLimitSample;
        'R': RunRetrySample;
        'T': RunTimeoutSample;
        'W': RunPolicyWrapSample;
      end;

    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

  Writeln;
  Writeln('Press enter to end...');
  Readln;
end.
