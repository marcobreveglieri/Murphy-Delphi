unit Murphy.Tests.Chaos.Fault;

interface

uses
  DUnitX.TestFramework;

type

{ TChaosFaultTests }

  [TestFixture]
  TChaosFaultTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestFaultBuilderCreatesPolicy;
    [Test]
    procedure TestFaultBuilderRejectsInvalidRate;
    [Test]
    procedure TestDefaultFaultIsInjected;
    [Test]
    procedure TestFaultWithClassAndMessage;
    [Test]
    procedure TestFaultWithClassAndDefaultMessage;
    [Test]
    procedure TestFaultGeneratorIsUsed;
    [Test]
    procedure TestFaultGeneratorReturningNilRunsAction;
    [Test]
    procedure TestNotInjectedRunsAction;
    [Test]
    procedure TestDisabledRunsAction;
    [Test]
    procedure TestGlobalSwitchRunsAction;
    [Test]
    procedure TestOnFaultInjectedReceivesFault;
    [Test]
    procedure TestOnFaultInjectedRaisingReplacesFault;
    [Test]
    procedure TestRetryRecoversFromInjectedFault;
  end;

implementation

uses
  System.SysUtils,
  Murphy.Chaos.Fault,
  Murphy.Globals,
  Murphy.Policy.Retry,
  Murphy.Policy.Wrap,
  Murphy.Resources.Strings,
  Murphy.Tests.Chaos.Helpers;

{ TChaosFaultTests }

procedure TChaosFaultTests.Setup;
begin
  // Skips the retry wait delays during tests.
  MurphyTestModeEnabled := True;
  MurphyChaosEnabled := True;
end;

procedure TChaosFaultTests.TearDown;
begin
  MurphyTestModeEnabled := False;
  MurphyChaosEnabled := True;
end;

procedure TChaosFaultTests.TestFaultBuilderCreatesPolicy;
begin
  var LPolicy := TChaosFaultBuilder.InjectionRate(0.1);
  Assert.IsNotNull(LPolicy);
  var LGeneratedPolicy := TChaosFaultBuilder.InjectionRateGenerator(
    function: Double
    begin
      Result := 0.1;
    end);
  Assert.IsNotNull(LGeneratedPolicy);
end;

procedure TChaosFaultTests.TestFaultBuilderRejectsInvalidRate;
begin
  Assert.WillRaise(
    procedure
    begin
      TChaosFaultBuilder.InjectionRate(2.0);
    end, EArgumentOutOfRangeException
  );
end;

procedure TChaosFaultTests.TestDefaultFaultIsInjected;
begin
  var LPolicy := TChaosFaultBuilder.InjectionRate(1.0);
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.AreEqual('EChaosFaultException', LFailure.ClassName);
  Assert.AreEqual(StrErrChaosFaultInjected, LFailure.Message);
  Assert.AreEqual(0, LExecutedCalls, 'The action must not run when a fault is injected');
end;

procedure TChaosFaultTests.TestFaultWithClassAndMessage;
begin
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .Fault(EInvalidOpException, 'Injected failure');
  var LFailure := ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual('Injected failure', LFailure.Message);
end;

procedure TChaosFaultTests.TestFaultWithClassAndDefaultMessage;
begin
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .Fault(EInvalidOpException);
  var LFailure := ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual(StrErrChaosFaultInjected, LFailure.Message);
end;

procedure TChaosFaultTests.TestFaultGeneratorIsUsed;
begin
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .FaultGenerator(
      function: Exception
      begin
        Result := ENotSupportedException.Create('Generated failure');
      end);
  var LFailure := ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual('ENotSupportedException', LFailure.ClassName);
  Assert.AreEqual('Generated failure', LFailure.Message);
end;

procedure TChaosFaultTests.TestFaultGeneratorReturningNilRunsAction;
begin
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .FaultGenerator(
      function: Exception
      begin
        Result := nil;
      end);
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TChaosFaultTests.TestNotInjectedRunsAction;
begin
  var LPolicy := TChaosFaultBuilder.InjectionRate(0.0);
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TChaosFaultTests.TestDisabledRunsAction;
begin
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .Enabled(False);
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TChaosFaultTests.TestGlobalSwitchRunsAction;
begin
  var LPolicy := TChaosFaultBuilder.InjectionRate(1.0);
  MurphyChaosEnabled := False;
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TChaosFaultTests.TestOnFaultInjectedReceivesFault;
begin
  var LCallbackClassName := '';
  var LCallbackMessage := '';
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .Fault(EInvalidOpException, 'Injected failure')
    .OnFaultInjected(
      procedure(AContext: TChaosFaultContext)
      begin
        Assert.IsNotNull(AContext);
        LCallbackClassName := AContext.Fault.ClassName;
        LCallbackMessage := AContext.Fault.Message;
      end);
  var LFailure := ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual('EInvalidOpException', LCallbackClassName);
  Assert.AreEqual('Injected failure', LCallbackMessage);
end;

procedure TChaosFaultTests.TestOnFaultInjectedRaisingReplacesFault;
begin
  // The fault is never raised, so the policy must destroy it: the
  // leak report of the chaos fixtures proves it.
  var LPolicy := TChaosFaultBuilder
    .InjectionRate(1.0)
    .Fault(EInvalidOpException)
    .OnFaultInjected(
      procedure(AContext: TChaosFaultContext)
      begin
        raise ENotSupportedException.Create('Callback failure');
      end);
  var LFailure := ExecuteCatching(LPolicy, procedure begin end);
  Assert.AreEqual('ENotSupportedException', LFailure.ClassName);
  Assert.AreEqual('Callback failure', LFailure.Message);
end;

procedure TChaosFaultTests.TestRetryRecoversFromInjectedFault;
begin
  // Chaos goes last in the wrap: the first two attempts get a fault
  // (0.1 < 0.5), the third one does not (0.9) and the retry recovers.
  var LInjectedFaults := 0;
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EChaosFaultException]).Retry(3),
    TChaosFaultBuilder
      .InjectionRate(0.5)
      .Randomizer(SequenceRandomizer([0.1, 0.1, 0.9]))
      .OnFaultInjected(
        procedure(AContext: TChaosFaultContext)
        begin
          Inc(LInjectedFaults);
        end)
  ]);
  var LExecutedCalls := 0;
  var LFailure := ExecuteCatching(LWrap,
    procedure
    begin
      Inc(LExecutedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(2, LInjectedFaults);
  Assert.AreEqual(1, LExecutedCalls);
end;

initialization
  TDUnitX.RegisterTestFixture(TChaosFaultTests);

end.
