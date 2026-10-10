unit Murphy.Tests.Chaos.Latency;

interface

uses
  DUnitX.TestFramework;

type

{ TChaosLatencyTests }

  [TestFixture]
  TChaosLatencyTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestLatencyBuilderCreatesPolicy;
    [Test]
    procedure TestLatencyBuilderRejectsInvalidRate;
    [Test]
    procedure TestInjectedLatencyRunsAction;
    [Test]
    procedure TestDefaultLatencyIsThirtySeconds;
    [Test]
    procedure TestLatencyGeneratorOverridesLatency;
    [Test]
    procedure TestNonPositiveLatencyIsNotInjected;
    [Test]
    procedure TestNotInjectedDoesNotFireCallback;
    [Test]
    procedure TestInjectedLatencyWaits;
    [Test]
    procedure TestTimeoutRejectsInjectedLatency;
  end;

implementation

uses
  System.Diagnostics,
  System.SyncObjs,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Chaos.Latency,
  Murphy.Globals,
  Murphy.Policy.Timeout,
  Murphy.Policy.Wrap,
  Murphy.Tests.Helpers;

{ TChaosLatencyTests }

procedure TChaosLatencyTests.Setup;
begin
  // Skips the injected delays, unless a test needs them.
  MurphyTestModeEnabled := True;
  MurphyChaosEnabled := True;
end;

procedure TChaosLatencyTests.TearDown;
begin
  MurphyTestModeEnabled := False;
  MurphyChaosEnabled := True;
end;

procedure TChaosLatencyTests.TestLatencyBuilderCreatesPolicy;
begin
  var LPolicy := TChaosLatencyBuilder.InjectionRate(0.1);
  Assert.IsNotNull(LPolicy);
  var LGeneratedPolicy := TChaosLatencyBuilder.InjectionRateGenerator(
    function: Double
    begin
      Result := 0.1;
    end);
  Assert.IsNotNull(LGeneratedPolicy);
end;

procedure TChaosLatencyTests.TestLatencyBuilderRejectsInvalidRate;
begin
  Assert.WillRaise(
    procedure
    begin
      TChaosLatencyBuilder.InjectionRate(-1.0);
    end, EArgumentOutOfRangeException
  );
end;

procedure TChaosLatencyTests.TestInjectedLatencyRunsAction;
begin
  var LInjectedLatency := TTimeSpan.Zero;
  var LPolicy := TChaosLatencyBuilder
    .InjectionRate(1.0)
    .Latency(TTimeSpan.FromSeconds(2))
    .OnLatencyInjected(
      procedure(AContext: TChaosLatencyContext)
      begin
        LInjectedLatency := AContext.Latency;
      end);
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(1, LExecutedCalls);
  Assert.AreEqual(2000.0, LInjectedLatency.TotalMilliseconds, 0.1);
end;

procedure TChaosLatencyTests.TestDefaultLatencyIsThirtySeconds;
begin
  // The default latency is 30 seconds, the same as Polly.
  var LInjectedLatency := TTimeSpan.Zero;
  var LPolicy := TChaosLatencyBuilder
    .InjectionRate(1.0)
    .OnLatencyInjected(
      procedure(AContext: TChaosLatencyContext)
      begin
        LInjectedLatency := AContext.Latency;
      end);
  ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual(30.0, LInjectedLatency.TotalSeconds, 0.001);
end;

procedure TChaosLatencyTests.TestLatencyGeneratorOverridesLatency;
begin
  var LInjectedLatency := TTimeSpan.Zero;
  var LPolicy := TChaosLatencyBuilder
    .InjectionRate(1.0)
    .Latency(TTimeSpan.FromSeconds(2))
    .LatencyGenerator(
      function: TTimeSpan
      begin
        Result := TTimeSpan.FromMilliseconds(500);
      end)
    .OnLatencyInjected(
      procedure(AContext: TChaosLatencyContext)
      begin
        LInjectedLatency := AContext.Latency;
      end);
  ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual(500.0, LInjectedLatency.TotalMilliseconds, 0.1);
end;

procedure TChaosLatencyTests.TestNonPositiveLatencyIsNotInjected;
begin
  var LGeneratedLatency := TTimeSpan.FromSeconds(-1);
  var LCallbackCalls := 0;
  var LPolicy := TChaosLatencyBuilder
    .InjectionRate(1.0)
    .LatencyGenerator(
      function: TTimeSpan
      begin
        Result := LGeneratedLatency;
      end)
    .OnLatencyInjected(
      procedure(AContext: TChaosLatencyContext)
      begin
        Inc(LCallbackCalls);
      end);
  var LExecutedCalls := 0;
  ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  LGeneratedLatency := TTimeSpan.Zero;
  ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.AreEqual(0, LCallbackCalls);
  Assert.AreEqual(2, LExecutedCalls);
end;

procedure TChaosLatencyTests.TestNotInjectedDoesNotFireCallback;
begin
  var LCallbackCalls := 0;
  var LPolicy := TChaosLatencyBuilder
    .InjectionRate(0.0)
    .OnLatencyInjected(
      procedure(AContext: TChaosLatencyContext)
      begin
        Inc(LCallbackCalls);
      end);
  var LExecutedCalls := 0;
  ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.AreEqual(0, LCallbackCalls);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TChaosLatencyTests.TestInjectedLatencyWaits;
begin
  MurphyTestModeEnabled := False;
  var LPolicy := TChaosLatencyBuilder
    .InjectionRate(1.0)
    .Latency(TTimeSpan.FromMilliseconds(300));
  var LStopwatch := TStopwatch.StartNew;
  ExecuteCatching(LPolicy, procedure begin end);
  // A small tolerance absorbs the timer resolution.
  Assert.IsTrue(LStopwatch.ElapsedMilliseconds >= 280,
    Format('Elapsed only %d ms', [LStopwatch.ElapsedMilliseconds]));
end;

procedure TChaosLatencyTests.TestTimeoutRejectsInjectedLatency;
begin
  // The injected latency exceeds the timeout around it: the timeout
  // rejects the call, proving how the timeout reacts to a slow call.
  MurphyTestModeEnabled := False;
  var LDone := TEvent.Create(nil, True, False, '');
  try
    var LWrap := TPolicyWrapBuilder.Wrap([
      TTimeoutBuilder.Handle([]).After(TTimeSpan.FromMilliseconds(200)),
      TChaosLatencyBuilder
        .InjectionRate(1.0)
        .Latency(TTimeSpan.FromMilliseconds(600))
    ]);
    var LFailure := ExecuteCatching(LWrap,
      procedure
      begin
        LDone.SetEvent;
      end);
    Assert.AreEqual('ETimeoutRejectedException', LFailure.ClassName);
    // The abandoned attempt keeps running in background: waits for
    // it before releasing the event it signals.
    Assert.IsTrue(LDone.WaitFor(5000) = TWaitResult.wrSignaled);
  finally
    LDone.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TChaosLatencyTests);

end.
