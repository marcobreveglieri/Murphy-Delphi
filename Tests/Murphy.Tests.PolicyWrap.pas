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
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Globals,
  Murphy.Policy.CircuitBreaker,
  Murphy.Policy.Hedging,
  Murphy.Policy.RateLimit,
  Murphy.Policy.Retry,
  Murphy.Policy.Timeout,
  Murphy.Policy.Wrap;

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

initialization
  TDUnitX.RegisterTestFixture(TPolicyWrapTests);

end.
