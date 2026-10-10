unit Samples.Chaos;

interface

procedure RunChaosSample;

implementation

uses
  System.Diagnostics,
  System.Rtti,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Chaos.Behavior,
  Murphy.Chaos.Fault,
  Murphy.Chaos.Latency,
  Murphy.Chaos.Outcome,
  Murphy.Globals,
  Murphy.Policy.CircuitBreaker,
  Murphy.Policy.Fallback,
  Murphy.Policy.Retry,
  Murphy.Policy.Timeout,
  Murphy.Policy.Wrap;

type
  EServiceUnavailableException = class(Exception);
  EHttpStatusException = class(Exception);

procedure RunFaultAndLatencyVsRetrySample;
begin
  // A healthy service made unreliable on purpose: the chaos policies
  // go last (innermost) in the wrap, so about half of the attempts get
  // a fault and about a third get a delay, and the retry around them
  // must cope with both.
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(EChaosFaultException)
      .Retry(5)
      .Wait(TTimeSpan.FromMilliseconds(500)),
    TChaosFaultBuilder
      .InjectionRate(0.5)
      .OnFaultInjected(
        procedure(AContext: TChaosFaultContext)
        begin
          Writeln('  Chaos: fault injected (', AContext.Fault.ClassName, ')');
        end),
    TChaosLatencyBuilder
      .InjectionRate(0.3)
      .Latency(TTimeSpan.FromSeconds(1))
      .OnLatencyInjected(
        procedure(AContext: TChaosLatencyContext)
        begin
          Writeln('  Chaos: latency injected (', AContext.Latency.TotalMilliseconds:0:0, ' ms)');
        end)
  ]);

  for var LCall := 1 to 5 do
  begin
    Writeln('Calling the service... (call no. ', LCall, ')');
    try
      LWrap.Execute(
        procedure
        begin
          Writeln('  Service reached!');
        end
      );
      Writeln('Call completed successfully!');
    except on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
    end;
    Writeln;
  end;
end;

procedure RunLatencyVsTimeoutSample;
begin
  // A fast service made slow on purpose: about half of the attempts
  // get a delay from 0.5 to 2.5 seconds. The timeout gives up on each
  // attempt after 1 second, and the retry around it starts a new one.
  Randomize;
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(ETimeoutRejectedException)
      .Retry(2)
      .Wait(TTimeSpan.FromMilliseconds(200)),
    TTimeoutBuilder
      .Handle([])
      .After(TTimeSpan.FromSeconds(1))
      .OnTimeout(
        procedure(AContext: TTimeoutContext)
        begin
          Writeln('  Timeout: attempt abandoned after ', AContext.ElapsedTime.TotalMilliseconds:0:0, ' ms');
        end),
    TChaosLatencyBuilder
      .InjectionRate(0.5)
      .LatencyGenerator(
        function: TTimeSpan
        begin
          // The generator runs at every injection: each delay differs.
          Result := TTimeSpan.FromMilliseconds(500 + Random(2000));
        end)
      .OnLatencyInjected(
        procedure(AContext: TChaosLatencyContext)
        begin
          Writeln('  Chaos: latency injected (', AContext.Latency.TotalMilliseconds:0:0, ' ms)');
        end)
  ]);

  for var LCall := 1 to 5 do
  begin
    Writeln('Calling the service... (call no. ', LCall, ')');
    var LStopwatch := TStopwatch.StartNew;
    try
      LWrap.Execute(
        procedure
        begin
          // Silent on purpose: the timeout does not stop an abandoned
          // attempt, which ends in background and would print later.
          Sleep(100);
        end
      );
      Writeln('Call completed successfully in ', LStopwatch.ElapsedMilliseconds, ' ms!');
    except on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
    end;
    Writeln;
  end;
end;

procedure RunFaultVsCircuitBreakerSample;
begin
  // A simulated outage: the injection rate follows a timeline, so every
  // call fails from 1.25 to 4.25 seconds and none fails before or after.
  // The circuit breaker opens after 2 failures in a row and rejects the
  // calls without reaching the service; after 1.25 seconds it lets one
  // trial call through (half-open), that closes the circuit on success
  // and opens it again on failure.
  var LClock := TStopwatch.StartNew;

  var LBreaker := TCircuitBreakerBuilder
    .Handle(EServiceUnavailableException)
    .Fail(2)
    .Within(TTimeSpan.FromMilliseconds(1250));

  var LWrap := TPolicyWrapBuilder.Wrap([
    LBreaker,
    TChaosFaultBuilder
      .InjectionRateGenerator(
        function: Double
        begin
          var LSeconds := LClock.Elapsed.TotalSeconds;
          if (LSeconds >= 1.25) and (LSeconds < 4.25) then
            Result := 1.0
          else
            Result := 0.0;
        end)
      .Fault(EServiceUnavailableException, 'Service unavailable (injected outage)')
  ]);

  for var LCall := 1 to 13 do
  begin
    Writeln(Format('[%.1f s] Calling the service... (call no. %d)',
      [LClock.Elapsed.TotalSeconds, LCall]));
    try
      LWrap.Execute(
        procedure
        begin
          Writeln('  Service reached!');
        end
      );
    except on E: Exception do
      Writeln('  ', E.ClassName, ': ', E.Message);
    end;
    Writeln('  Circuit now: ', TRttiEnumerationType.GetName<TCircuitState>(LBreaker.CircuitState));
    Writeln;
    Sleep(500);
  end;
end;

function SendRateRequest: Integer;
begin
  // The real service: it always answers "200 OK".
  Result := 200;
end;

function CreateFakeResponsePolicy: IChaosOutcomePolicy<Integer>;
begin
  // About half of the requests get a fake "503 Service Unavailable"
  // instead of the real answer. The policy is built in its own routine
  // because all the closures of a routine share one frame: if the
  // routine that captures the policy also created these closures, the
  // policy and the frame would reference each other and leak.
  Result := TChaosOutcomeBuilder<Integer>
    .InjectionRate(0.5)
    .Outcome(
      function: Integer
      begin
        Result := 503;
      end)
    .OnOutcomeInjected(
      procedure(AContext: TChaosOutcomeContext<Integer>)
      begin
        Writeln('  Chaos: fake response injected (HTTP ', AContext.Outcome, ')');
      end);
end;

procedure RunOutcomeVsFallbackSample;
begin
  // Chaos Outcome works on functions, so it cannot join a policy wrap:
  // it is called inside the function executed by the other policies.
  // The client turns an error status into an exception, the retry asks
  // again, and when the retry gives up the fallback serves a cached rate.
  var LChaos := CreateFakeResponsePolicy;

  var LRetry := TRetryBuilder
    .Handle(EHttpStatusException)
    .Retry(1)
    .Wait(TTimeSpan.FromMilliseconds(300));

  var LFallback := TFallbackBuilder<string>
    .Handle(EHttpStatusException)
    .Fallback(
      function: string
      begin
        Result := 'EUR/USD 1.0800 (cached)';
      end);

  for var LCall := 1 to 6 do
  begin
    Writeln('Asking for the exchange rate... (call no. ', LCall, ')');
    var LRate := LFallback.Execute(
      function: string
      begin
        LRetry.Execute(
          procedure
          begin
            var LStatus := LChaos.Execute(SendRateRequest);
            Writeln('  Response: HTTP ', LStatus);
            if LStatus <> 200 then
              raise EHttpStatusException.CreateFmt('HTTP status %d', [LStatus]);
          end
        );
        Result := 'EUR/USD 1.0842 (live)';
      end
    );
    Writeln('Exchange rate: ', LRate);
    Writeln;
  end;
end;

procedure RunBehaviorBlastRadiusSample;
const
  CUsers: array[0..2] of string = ('alice', 'tester', 'bob');
begin
  // The behavior drops the database connection before the query runs,
  // to test the reconnection logic of the application. The blast radius
  // is kept small: chaos is enabled only for the "tester" user, and the
  // master switch turns off every chaos policy at once.
  var LConnected := True;
  var LUser := '';

  var LChaos := TChaosBehaviorBuilder
    .InjectionRate(1.0)
    .EnabledGenerator(
      function: Boolean
      begin
        Result := LUser = 'tester';
      end)
    .Behavior(
      procedure
      begin
        LConnected := False;
      end)
    .OnBehaviorInjected(
      procedure(AContext: TChaosBehaviorContext)
      begin
        Writeln('  Chaos: database connection dropped');
      end);

  try
    for var LPass := 1 to 2 do
    begin
      if LPass = 2 then
      begin
        // E.g. in production builds.
        MurphyChaosEnabled := False;
        Writeln('Master switch off (MurphyChaosEnabled = False):');
      end
      else
        Writeln('Chaos only for the "tester" user:');
      Writeln;

      for var LIndex := Low(CUsers) to High(CUsers) do
      begin
        LUser := CUsers[LIndex];
        Writeln('Running the query for ', LUser, '...');
        LChaos.Execute(
          procedure
          begin
            // The resilience under test.
            if not LConnected then
            begin
              Writeln('  Connection lost: reconnecting...');
              LConnected := True;
            end;
            Writeln('  Query executed!');
          end
        );
      end;
      Writeln;
    end;
  finally
    MurphyChaosEnabled := True;
  end;
end;

procedure RunChaosSample;
begin
  while True do
  begin
    Writeln('--------------------');
    Writeln('1) Fault and Latency vs Retry');
    Writeln('2) Latency vs Timeout');
    Writeln('3) Fault vs Circuit Breaker (simulated outage)');
    Writeln('4) Outcome vs Fallback (fake responses)');
    Writeln('5) Behavior with a limited blast radius');
    Writeln('             Q) back');
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
      '1': RunFaultAndLatencyVsRetrySample;
      '2': RunLatencyVsTimeoutSample;
      '3': RunFaultVsCircuitBreakerSample;
      '4': RunOutcomeVsFallbackSample;
      '5': RunBehaviorBlastRadiusSample;
    end;

  end;
end;

end.
