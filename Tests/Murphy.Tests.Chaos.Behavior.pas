unit Murphy.Tests.Chaos.Behavior;

interface

uses
  DUnitX.TestFramework;

type

{ TChaosBehaviorTests }

  [TestFixture]
  TChaosBehaviorTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestBehaviorBuilderCreatesPolicy;
    [Test]
    procedure TestBehaviorBuilderRejectsInvalidRate;
    [Test]
    procedure TestBehaviorRunsBeforeAction;
    [Test]
    procedure TestOnBehaviorInjectedRunsAfterBehavior;
    [Test]
    procedure TestBehaviorExceptionSkipsAction;
    [Test]
    procedure TestNotInjectedSkipsBehavior;
    [Test]
    procedure TestNoBehaviorRunsAction;
    [Test]
    procedure TestRetryRecoversFromInjectedBehavior;
  end;

implementation

uses
  System.SysUtils,
  Murphy.Chaos.Behavior,
  Murphy.Globals,
  Murphy.Policy.Retry,
  Murphy.Policy.Wrap,
  Murphy.Tests.Helpers;

{ TChaosBehaviorTests }

procedure TChaosBehaviorTests.Setup;
begin
  // Skips the retry wait delays during tests.
  MurphyTestModeEnabled := True;
  MurphyChaosEnabled := True;
end;

procedure TChaosBehaviorTests.TearDown;
begin
  MurphyTestModeEnabled := False;
  MurphyChaosEnabled := True;
end;

procedure TChaosBehaviorTests.TestBehaviorBuilderCreatesPolicy;
begin
  var LPolicy := TChaosBehaviorBuilder.InjectionRate(0.1);
  Assert.IsNotNull(LPolicy);
  var LGeneratedPolicy := TChaosBehaviorBuilder.InjectionRateGenerator(
    function: Double
    begin
      Result := 0.1;
    end);
  Assert.IsNotNull(LGeneratedPolicy);
end;

procedure TChaosBehaviorTests.TestBehaviorBuilderRejectsInvalidRate;
begin
  Assert.WillRaise(
    procedure
    begin
      TChaosBehaviorBuilder.InjectionRate(1.5);
    end, EArgumentOutOfRangeException
  );
end;

procedure TChaosBehaviorTests.TestBehaviorRunsBeforeAction;
begin
  var LTrace := '';
  var LPolicy := TChaosBehaviorBuilder
    .InjectionRate(1.0)
    .Behavior(
      procedure
      begin
        LTrace := LTrace + 'B';
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      LTrace := LTrace + 'A';
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual('BA', LTrace);
end;

procedure TChaosBehaviorTests.TestOnBehaviorInjectedRunsAfterBehavior;
begin
  var LTrace := '';
  var LPolicy := TChaosBehaviorBuilder
    .InjectionRate(1.0)
    .Behavior(
      procedure
      begin
        LTrace := LTrace + 'B';
      end)
    .OnBehaviorInjected(
      procedure(AContext: TChaosBehaviorContext)
      begin
        Assert.IsNotNull(AContext);
        LTrace := LTrace + 'C';
      end);
  ExecuteCatching(LPolicy,
    procedure
    begin
      LTrace := LTrace + 'A';
    end);
  Assert.AreEqual('BCA', LTrace);
end;

procedure TChaosBehaviorTests.TestBehaviorExceptionSkipsAction;
begin
  var LTrace := '';
  var LPolicy := TChaosBehaviorBuilder
    .InjectionRate(1.0)
    .Behavior(
      procedure
      begin
        raise ENotSupportedException.Create('Behavior failure');
      end)
    .OnBehaviorInjected(
      procedure(AContext: TChaosBehaviorContext)
      begin
        LTrace := LTrace + 'C';
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      LTrace := LTrace + 'A';
    end);
  Assert.AreEqual('ENotSupportedException', LFailure.ClassName);
  Assert.AreEqual('Behavior failure', LFailure.Message);
  Assert.AreEqual('', LTrace, 'Neither the callback nor the action must run');
end;

procedure TChaosBehaviorTests.TestNotInjectedSkipsBehavior;
begin
  var LTrace := '';
  var LPolicy := TChaosBehaviorBuilder
    .InjectionRate(0.0)
    .Behavior(
      procedure
      begin
        LTrace := LTrace + 'B';
      end);
  ExecuteCatching(LPolicy,
    procedure
    begin
      LTrace := LTrace + 'A';
    end);
  Assert.AreEqual('A', LTrace);
end;

procedure TChaosBehaviorTests.TestNoBehaviorRunsAction;
begin
  var LTrace := '';
  var LPolicy := TChaosBehaviorBuilder
    .InjectionRate(1.0)
    .OnBehaviorInjected(
      procedure(AContext: TChaosBehaviorContext)
      begin
        LTrace := LTrace + 'C';
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      LTrace := LTrace + 'A';
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual('A', LTrace);
end;

procedure TChaosBehaviorTests.TestRetryRecoversFromInjectedBehavior;
begin
  // The behavior drops the connection before the first attempt only
  // (0.1 < 0.5, then 0.9): the action fails once, reconnects, and the
  // retry around the chaos policy recovers.
  var LConnected := True;
  var LCompletedCalls := 0;
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder.Handle([EInvalidOpException]).Retry(3),
    TChaosBehaviorBuilder
      .InjectionRate(0.5)
      .Randomizer(SequenceRandomizer([0.1, 0.9]))
      .Behavior(
        procedure
        begin
          LConnected := False;
        end)
  ]);
  var LFailure := ExecuteCatching(LWrap,
    procedure
    begin
      if not LConnected then
      begin
        LConnected := True;
        raise EInvalidOpException.Create('Connection lost');
      end;
      Inc(LCompletedCalls);
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(1, LCompletedCalls);
end;

initialization
  TDUnitX.RegisterTestFixture(TChaosBehaviorTests);

end.
