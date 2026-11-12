unit Murphy.Tests.PolicyWrap;

interface

uses
  DUnitX.TestFramework;

type

{ TPolicyWrapTests }

  [TestFixture]
  TPolicyWrapTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestWrapCreate;
    [Test]
    procedure TestWrapEmptyRaises;
    [Test]
    procedure TestWrapSinglePolicyExecutes;
    [Test]
    procedure TestRetryAroundBreaker;
    [Test]
    procedure TestBreakerAroundRetry;
    [Test]
    procedure TestWrapWithTimeoutInsideRetry;
    [Test]
    procedure TestNestedWrap;
    [Test]
    procedure TestWrapWithHedging;
    [Test]
    procedure TestGenericWrapFallbackAroundRetryReturnsFallback;
    [Test]
    procedure TestGenericWrapFallbackAroundRetryReturnsRealValue;
    [Test]
    procedure TestGenericWrapRetryAroundTimeoutReturnsLastAttempt;
    [Test]
    procedure TestGenericWrapWithCache;
    [Test]
    procedure TestGenericWrapWithChaosOutcome;
    [Test]
    procedure TestGenericWrapNested;
    [Test]
    procedure TestGenericWrapEmptyRaises;
    [Test]
    procedure TestGenericWrapNilPolicyRaises;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Policy,
  Murphy.Chaos.Outcome,
  Murphy.Globals,
  Murphy.Policy.Cache,
  Murphy.Policy.CircuitBreaker,
  Murphy.Policy.Fallback,
  Murphy.Policy.Hedging,
  Murphy.Policy.RateLimit,
  Murphy.Policy.Retry,
  Murphy.Policy.Timeout,
  Murphy.Policy.Wrap;

// The generic wraps below are built in separate routines: their closures
// live in these frames, so the test closures never share a frame with a
// policy and no reference cycle (hence no leak) can be created.

function FallbackAroundRetry: IPolicyWrap<string>;
begin
  Result := TPolicyWrapBuilder<string>.Wrap([
    TFallbackBuilder<string>
      .Handle([EInvalidOpException])
      .Fallback(function: string begin Result := 'fallback'; end),
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3)
  ]);
end;

function RetryAroundTimeout: IPolicyWrap<string>;
begin
  Result := TPolicyWrapBuilder<string>.Wrap([
    TRetryBuilder.Handle([ETimeoutRejectedException]).Retry(1),
    TTimeoutBuilder.Handle([]).After(TTimeSpan.FromMilliseconds(200))
  ]);
end;

function RetryAroundCache: IPolicyWrap<Integer>;
begin
  Result := TPolicyWrapBuilder<Integer>.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(1),
    TCacheBuilder<Integer>.Handle([]).Expire(TTimeSpan.FromMinutes(1))
  ]);
end;

function RetryAroundChaosOutcome: IPolicyWrap<string>;
begin
  Result := TPolicyWrapBuilder<string>.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(1),
    TChaosOutcomeBuilder<string>
      .InjectionRate(1.0)
      .Outcome(function: string begin Result := 'injected'; end)
  ]);
end;

function NestedGenericWrap: IPolicyWrap<string>;
begin
  var LInner := TPolicyWrapBuilder<string>.Wrap([
    TFallbackBuilder<string>
      .Handle([EInvalidOpException])
      .Fallback(function: string begin Result := 'inner fallback'; end)
  ]);
  Result := TPolicyWrapBuilder<string>.Wrap([
    TRetryBuilder.Handle([EFileNotFoundException]).Retry(1),
    LInner
  ]);
end;

{ TPolicyWrapTests }

procedure TPolicyWrapTests.Setup;
begin
  // Skips the retry wait delays during tests.
  MurphyTestModeEnabled := True;
end;

procedure TPolicyWrapTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TPolicyWrapTests.TestWrapCreate;
begin
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3),
    TRateLimitBuilder.Handle([]).Allow(10).Within(TTimeSpan.FromSeconds(1))
  ]);
  Assert.IsNotNull(LWrap);
end;

procedure TPolicyWrapTests.TestWrapEmptyRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPolicyWrapBuilder.Wrap([]);
    end, EArgumentException
  );
end;

procedure TPolicyWrapTests.TestWrapSinglePolicyExecutes;
begin
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3)
  ]);
  var LExecutedCalls := 0;
  LWrap.Execute(
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TPolicyWrapTests.TestRetryAroundBreaker;
begin
  // The action always fails: the breaker opens after 2 failures, so
  // the third pass hits an open circuit and EBrokenCircuitException
  // escapes the retry (which does not handle it), proving that the
  // policies apply outermost-first.
  var LBreaker := TCircuitBreakerBuilder
    .Handle([EInvalidOpException])
    .Fail(2)
    .Within(TTimeSpan.FromSeconds(30));
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3),
    LBreaker
  ]);
  Assert.WillRaise(
    procedure
    begin
      LWrap.Execute(
        procedure
        begin
          raise EInvalidOpException.Create('Test failure');
        end);
    end, EBrokenCircuitException
  );
  Assert.IsTrue(LBreaker.CircuitState = TCircuitState.Open);
end;

procedure TPolicyWrapTests.TestBreakerAroundRetry;
begin
  // The retry absorbs the first two failures before the breaker can
  // see them, so the overall call succeeds and the circuit is closed.
  var LBreaker := TCircuitBreakerBuilder
    .Handle([EInvalidOpException])
    .Fail(2)
    .Within(TTimeSpan.FromSeconds(30));
  var LWrap := TPolicyWrapBuilder.Wrap([
    LBreaker,
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3)
  ]);
  var LAttempts := 0;
  Assert.WillNotRaise(
    procedure
    begin
      LWrap.Execute(
        procedure
        begin
          Inc(LAttempts);
          if LAttempts <= 2 then
            raise EInvalidOpException.Create('Test failure');
        end);
    end
  );
  Assert.AreEqual(3, LAttempts);
  Assert.IsTrue(LBreaker.CircuitState = TCircuitState.Closed);
end;

procedure TPolicyWrapTests.TestWrapWithTimeoutInsideRetry;
begin
  // The first attempt exceeds the timeout; the retry handles the
  // timeout rejection and the second, faster attempt succeeds.
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([ETimeoutRejectedException]).Retry(1),
    TTimeoutBuilder.Handle([]).After(TTimeSpan.FromMilliseconds(200))
  ]);
  var LAttempts := 0;
  Assert.WillNotRaise(
    procedure
    begin
      LWrap.Execute(
        procedure
        begin
          Inc(LAttempts);
          if LAttempts = 1 then
            TThread.Sleep(600);
        end);
    end
  );
  Assert.AreEqual(2, LAttempts);
end;

procedure TPolicyWrapTests.TestNestedWrap;
begin
  var LInnerWrap := TPolicyWrapBuilder.Wrap([
    TRateLimitBuilder.Handle([]).Allow(10).Within(TTimeSpan.FromSeconds(1))
  ]);
  var LOuterWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3),
    LInnerWrap
  ]);
  var LExecutedCalls := 0;
  LOuterWrap.Execute(
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TPolicyWrapTests.TestWrapWithHedging;
begin
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(1),
    THedgingBuilder.Handle([EInvalidOpException]).MaxAttempts(1).Delay(TTimeSpan.FromSeconds(2))
  ]);
  var LExecutedCalls := 0;
  LWrap.Execute(
    procedure
    begin
      TInterlocked.Increment(LExecutedCalls);
    end);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TPolicyWrapTests.TestGenericWrapFallbackAroundRetryReturnsFallback;
begin
  var LWrap := FallbackAroundRetry;
  var LCalls := 0;
  var LResult := LWrap.Execute(
    function: string
    begin
      Inc(LCalls);
      raise EInvalidOpException.Create('Test failure');
    end);
  // The retry exhausts its attempts, then the fallback gives the value.
  Assert.AreEqual('fallback', LResult);
  Assert.AreEqual(4, LCalls);
end;

procedure TPolicyWrapTests.TestGenericWrapFallbackAroundRetryReturnsRealValue;
begin
  var LWrap := FallbackAroundRetry;
  var LCalls := 0;
  var LResult := LWrap.Execute(
    function: string
    begin
      Inc(LCalls);
      if LCalls <= 2 then
        raise EInvalidOpException.Create('Test failure');
      Result := 'real value';
    end);
  // The value comes out of the retry, which is an executable policy.
  Assert.AreEqual('real value', LResult);
  Assert.AreEqual(3, LCalls);
end;

procedure TPolicyWrapTests.TestGenericWrapRetryAroundTimeoutReturnsLastAttempt;
begin
  var LWrap := RetryAroundTimeout;
  var LAttempts := 0;
  var LResult := LWrap.Execute(
    function: string
    begin
      if TInterlocked.Increment(LAttempts) = 1 then
      begin
        // Abandoned by the timeout: its late value must not leak out.
        TThread.Sleep(600);
        Result := 'late';
      end
      else
        Result := 'second attempt';
    end);
  Assert.AreEqual('second attempt', LResult);
  Assert.AreEqual(2, LAttempts);
end;

procedure TPolicyWrapTests.TestGenericWrapWithCache;
begin
  var LWrap := RetryAroundCache;
  var LCalls := 0;
  var LFirst := LWrap.Execute(
    function: Integer
    begin
      Inc(LCalls);
      Result := 42;
    end);
  var LSecond := LWrap.Execute(
    function: Integer
    begin
      Inc(LCalls);
      Result := 99;
    end);
  Assert.AreEqual(42, LFirst);
  Assert.AreEqual(42, LSecond, 'The cached value must be served');
  Assert.AreEqual(1, LCalls);
end;

procedure TPolicyWrapTests.TestGenericWrapWithChaosOutcome;
begin
  var LWrap := RetryAroundChaosOutcome;
  var LCalls := 0;
  var LResult := LWrap.Execute(
    function: string
    begin
      Inc(LCalls);
      Result := 'real';
    end);
  Assert.AreEqual('injected', LResult);
  Assert.AreEqual(0, LCalls, 'The real function must not run');
end;

procedure TPolicyWrapTests.TestGenericWrapNested;
begin
  var LWrap := NestedGenericWrap;
  var LResult := LWrap.Execute(
    function: string
    begin
      raise EInvalidOpException.Create('Test failure');
    end);
  Assert.AreEqual('inner fallback', LResult);
end;

procedure TPolicyWrapTests.TestGenericWrapEmptyRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TPolicyWrapBuilder<string>.Wrap([]);
    end, EArgumentException
  );
end;

procedure TPolicyWrapTests.TestGenericWrapNilPolicyRaises;
begin
  var LMissing: IRetryPolicy := nil;
  Assert.WillRaise(
    procedure
    begin
      TPolicyWrapBuilder<string>.Wrap([LMissing]);
    end, EArgumentException
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TPolicyWrapTests);

end.
