unit Murphy.Tests.CircuitBreaker;

interface

uses
  DUnitX.TestFramework;

type

{ TCircuitBreakerTests }

  [TestFixture]
  TCircuitBreakerTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestCircuitBreakerHandle;
    [Test]
    procedure TestCircuitOpensAfterFailureThreshold;
    [Test]
    procedure TestOpenCircuitBlocksCalls;
    [Test]
    procedure TestBrokenCircuitExceptionCarriesInnerException;
    [Test]
    procedure TestSuccessResetsFailureCount;
    [Test]
    procedure TestIsolateBlocksCalls;
    [Test]
    procedure TestResetClosesCircuit;
  end;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Globals,
  Murphy.Policy.CircuitBreaker,
  Murphy.Tests.Helpers;

{ TCircuitBreakerTests }

procedure TCircuitBreakerTests.Setup;
begin
  // Freezes the clock: an open circuit never expires during tests.
  MurphyTestModeEnabled := True;
end;

procedure TCircuitBreakerTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TCircuitBreakerTests.TestCircuitBreakerHandle;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException);
  Assert.IsNotNull(LPolicy);
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Closed);
end;

procedure TCircuitBreakerTests.TestCircuitOpensAfterFailureThreshold;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException)
    .Fail(2);
  var LFailingProc: TProc :=
    procedure
    begin
      raise EInvalidOpException.Create('Error Message');
    end;
  var LFailure := ExecuteCatching(LPolicy, LFailingProc);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Closed);
  LFailure := ExecuteCatching(LPolicy, LFailingProc);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Open);
end;

procedure TCircuitBreakerTests.TestOpenCircuitBlocksCalls;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException)
    .Fail(1)
    .Within(TTimeSpan.FromSeconds(30));
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          raise EInvalidOpException.Create('Error Message');
        end);
    end, EInvalidOpException
  );
  var LExecuted := False;
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          LExecuted := True;
        end);
    end, EBrokenCircuitException
  );
  Assert.IsFalse(LExecuted, 'Action should not run while the circuit is open');
end;

procedure TCircuitBreakerTests.TestBrokenCircuitExceptionCarriesInnerException;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException)
    .Fail(1);
  try
    LPolicy.Execute(
      procedure
      begin
        raise EInvalidOpException.Create('Error Message');
      end);
  except
    on EInvalidOpException do
      ; // Expected: the policy re-raises the handled exception.
  end;
  try
    LPolicy.Execute(
      procedure
      begin
      end);
    Assert.Fail('EBrokenCircuitException expected');
  except
    on E: EBrokenCircuitException do
    begin
      Assert.IsNotNull(E.InnerException);
      Assert.IsTrue(E.InnerException is EInvalidOpException);
      Assert.AreEqual('Error Message', E.InnerException.Message);
    end;
  end;
end;

procedure TCircuitBreakerTests.TestSuccessResetsFailureCount;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException)
    .Fail(2);
  var LFailingProc: TProc :=
    procedure
    begin
      raise EInvalidOpException.Create('Error Message');
    end;
  var LFailure := ExecuteCatching(LPolicy, LFailingProc);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  // A successful call heals the failure count...
  LPolicy.Execute(
    procedure
    begin
    end);
  // ...so the next single failure must not open the circuit.
  LFailure := ExecuteCatching(LPolicy, LFailingProc);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Closed);
end;

procedure TCircuitBreakerTests.TestIsolateBlocksCalls;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException);
  LPolicy.Isolate;
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Isolated);
  var LExecuted := False;
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          LExecuted := True;
        end);
    end, EBrokenCircuitException
  );
  Assert.IsFalse(LExecuted, 'Action should not run while the circuit is isolated');
end;

procedure TCircuitBreakerTests.TestResetClosesCircuit;
begin
  var LPolicy := TCircuitBreakerBuilder
    .Handle(EInvalidOpException)
    .Fail(1);
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          raise EInvalidOpException.Create('Error Message');
        end);
    end, EInvalidOpException
  );
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Open);
  LPolicy.Reset;
  Assert.IsTrue(LPolicy.CircuitState = TCircuitState.Closed);
  Assert.WillNotRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
        end);
    end
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TCircuitBreakerTests);

end.
